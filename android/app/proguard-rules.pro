# Flutter rules are automatically applied by the Flutter Gradle Plugin.

# SQLCipher / Zetetic keep rules for R8 minification
-keep class net.zetetic.database.** { *; }
-keep class net.zetetic.database.sqlcipher.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
