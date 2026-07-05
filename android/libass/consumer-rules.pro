# JNI exports bind by name (Java_nl_michelknoop_pleya_libass_*); keep the names stable.
-keepclasseswithmembernames class nl.michelknoop.pleya.libass.* {
    native <methods>;
}
