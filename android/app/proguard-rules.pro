# LibReady R8 rules.
#
# Flutter plugins are reached through reflection/platform channels, so keep the
# plugin entry points and Pigeon-generated classes that R8 cannot see.

-keep class io.flutter.plugins.** { *; }
-keep class com.tekartik.sqflite.** { *; }

-dontwarn io.flutter.embedding.**
