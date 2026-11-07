# Preserve XML parser interfaces used by share_plus FileProvider under R8.
# https://stackoverflow.com/questions/78049204/java-lang-incompatibleclasschangeerror-class-android-content-res-xmlblockpars
-keep class org.xmlpull.v1.** { *; }

# Dart JNI resolves Pigeon suspend methods using this exact parameter type.
-keep class kotlin.coroutines.Continuation { *; }
