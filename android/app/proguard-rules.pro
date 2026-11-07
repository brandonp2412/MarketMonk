-dontobfuscate

# Preserve XML parser interfaces used by share_plus FileProvider under R8.
# https://stackoverflow.com/questions/78049204/java-lang-incompatibleclasschangeerror-class-android-content-res-xmlblockpars
-keep class org.xmlpull.v1.** { *; }

# Dart JNI resolves these Kotlin classes and members by name.
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
