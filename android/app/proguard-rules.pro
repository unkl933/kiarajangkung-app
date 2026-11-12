# Aturan untuk menjaga plugin scanner/camera agar tidak rusak saat release
-keep class com.google.zxing.** { *; }
-keep class journeyapps.barcodescanner.** { *; }
-dontwarn com.google.zxing.**

# Menjaga plugin mobile_scanner
-keep class dev.datastorage.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
