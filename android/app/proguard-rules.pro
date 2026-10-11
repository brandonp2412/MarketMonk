# Preserve XML parser interfaces used by share_plus FileProvider under R8.
# https://stackoverflow.com/questions/78049204/java-lang-incompatibleclasschangeerror-class-android-content-res-xmlblockpars
-keep class org.xmlpull.v1.** { *; }
