# R8은 호출부를 못 찾으면 지운다. 아래 것들은 호출부가 Dart 쪽이거나
# 리플렉션이라 바이트코드에 흔적이 없다 — 지워지면 릴리스에서만 죽는다.

# Flutter 엔진과 플러그인 등록부
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# MapLibre: 네이티브(JNI)에서 부르는 것이 많다
-keep class org.maplibre.android.** { *; }
-keep class com.mapbox.** { *; }
-dontwarn org.maplibre.android.**

# Play Core: Flutter의 지연 로딩 경로가 참조하지만 우리는 쓰지 않는다
-dontwarn com.google.android.play.core.**

# 스택 트레이스를 읽을 수 있게 줄 번호를 남긴다
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
