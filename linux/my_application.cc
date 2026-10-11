#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkSettings* gtk_settings;
  GDBusProxy* appearance_portal;
  gboolean default_prefer_dark;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Settings.html
static void apply_color_scheme(MyApplication* self, GVariant* value) {
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
    g_autoptr(GVariant) unboxed = g_variant_get_variant(value);
    apply_color_scheme(self, unboxed);
    return;
  }
  if (!g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
    return;
  }
  const guint32 scheme = g_variant_get_uint32(value);
  if (scheme <= 2) {
    g_object_set(self->gtk_settings, "gtk-application-prefer-dark-theme",
                 scheme == 0 ? self->default_prefer_dark : scheme == 1,
                 nullptr);
  }
}

static void portal_setting_changed(GDBusProxy* proxy, const gchar* sender,
                                   const gchar* signal, GVariant* parameters,
                                   gpointer user_data) {
  if (g_strcmp0(signal, "SettingChanged") != 0) {
    return;
  }
  const gchar* namespace_name;
  const gchar* key;
  g_autoptr(GVariant) value = nullptr;
  g_variant_get(parameters, "(&s&s@v)", &namespace_name, &key, &value);
  if (g_strcmp0(namespace_name, "org.freedesktop.appearance") == 0 &&
      g_strcmp0(key, "color-scheme") == 0) {
    apply_color_scheme(MY_APPLICATION(user_data), value);
  }
}

static void portal_read_finished(GObject* source, GAsyncResult* result,
                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_proxy_call_finish(G_DBUS_PROXY(source), result, &error);
  if (reply != nullptr) {
    g_autoptr(GVariant) value = g_variant_get_child_value(reply, 0);
    apply_color_scheme(self, value);
  }
  g_object_unref(self);
}

static void portal_connected(GObject* source, GAsyncResult* result,
                             gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;
  self->appearance_portal = g_dbus_proxy_new_for_bus_finish(result, &error);
  if (self->appearance_portal != nullptr) {
    g_signal_connect(self->appearance_portal, "g-signal",
                     G_CALLBACK(portal_setting_changed), self);
    g_dbus_proxy_call(self->appearance_portal, "Read",
                      g_variant_new("(ss)", "org.freedesktop.appearance",
                                    "color-scheme"),
                      G_DBUS_CALL_FLAGS_NONE, -1, nullptr,
                      portal_read_finished, g_object_ref(self));
  }
  g_object_unref(self);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    self->gtk_settings = gtk_settings_get_for_screen(gtk_window_get_screen(window));
    g_autofree gchar* theme_name = nullptr;
    g_object_get(self->gtk_settings, "gtk-theme-name", &theme_name, nullptr);
    if (g_strcmp0(theme_name, "Adwaita-dark") == 0) {
      g_object_set(self->gtk_settings, "gtk-theme-name", "Adwaita",
                   "gtk-application-prefer-dark-theme", TRUE, nullptr);
    }
    g_object_get(self->gtk_settings, "gtk-application-prefer-dark-theme",
                 &self->default_prefer_dark, nullptr);
    g_dbus_proxy_new_for_bus(
        G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_NONE, nullptr,
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Settings", nullptr, portal_connected,
        g_object_ref(self));

    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Market Monk");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Market Monk");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_enable_impeller(project, FALSE);
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->appearance_portal);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
