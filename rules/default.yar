rule Android_Suspicious_Permissions {
    meta:
        description = "Detects APKs requesting dangerous permission combinations"
    strings:
        $p1 = "android.permission.SEND_SMS"
        $p2 = "android.permission.READ_CONTACTS"
        $p3 = "android.permission.CAMERA"
        $p4 = "android.permission.RECORD_AUDIO"
        $p5 = "android.permission.ACCESS_FINE_LOCATION"
        $p6 = "android.permission.READ_PHONE_STATE"
        $p7 = "android.permission.READ_EXTERNAL_STORAGE"
        $p8 = "android.permission.WRITE_EXTERNAL_STORAGE"
        $p9 = "android.permission.READ_CALL_LOG"
        $p10 = "android.permission.WRITE_CALL_LOG"
        $p11 = "android.permission.CALL_PHONE"
        $p12 = "android.permission.PROCESS_OUTGOING_CALLS"
        $p13 = "android.permission.SYSTEM_ALERT_WINDOW"
        $p14 = "android.permission.WRITE_SETTINGS"
        $p15 = "android.permission.INSTALL_PACKAGES"
        $p16 = "android.permission.RECEIVE_BOOT_COMPLETED"
        $p17 = "android.permission.BIND_ACCESSIBILITY_SERVICE"
        $p18 = "android.permission.BIND_DEVICE_ADMIN"
    condition:
        3 of them
}

rule Android_Hardcoded_Credentials {
    meta:
        description = "Detects hardcoded credentials in APK"
    strings:
        $pass1 = /password\s*[=:]\s*"[^"]{4,}"/ nocase
        $pass2 = /passwd\s*[=:]\s*"[^"]{4,}"/ nocase
        $pass3 = /secret\s*[=:]\s*"[^"]{4,}"/ nocase
        $key1 = /api[_-]?key\s*[=:]\s*"[A-Za-z0-9]{8,}"/ nocase
        $key2 = /auth[_-]?token\s*[=:]\s*"[A-Za-z0-9]{8,}"/ nocase
        $aws = /AKIA[0-9A-Z]{16}/
        $google = /AIza[0-9A-Za-z_]{35}/
    condition:
        2 of them
}

rule Android_Crypto_Misuse {
    meta:
        description = "Detects weak or suspicious crypto usage"
    strings:
        $des = "DES"
        $desede = "DESede"
        $md5 = "MD5"
        $rc4 = "RC4"
        $ecb = "ECB"
        $weak = "NoPadding"
        $hardcoded_iv = /IvParameterSpec\s*\(\s*"/
        $hardcoded_key = /SecretKeySpec\s*\(\s*"/
    condition:
        2 of them
}

rule Android_Network_Security {
    meta:
        description = "Detects insecure network configurations"
    strings:
        $cleartext = /usesCleartextTraffic\s*=\s*"true"/
        $trust_all = /TrustAllCertificates|ALLOW_ALL_HOSTNAME|AllowAll/
        $no_verify = /hostnameVerifier\s*\(\s*.*allowAll/
        $http = /http:\/\/[^\s"]+/
    condition:
        2 of them
}

rule Android_Root_Detection_Bypass {
    meta:
        description = "Detects root detection and bypass patterns"
    strings:
        $su_check = "/system/bin/su"
        $superuser = "/system/app/Superuser"
        $magisk = "com.topjohnwu.magisk"
        $busybox = "busybox"
        $rootbeer = "RootBeer"
        $safetynet = "SafetyNet"
    condition:
        2 of them
}

rule Android_Dynamic_Loading {
    meta:
        description = "Detects dynamic code loading patterns"
    strings:
        $dexloader = "DexClassLoader"
        $pathloader = "PathClassLoader"
        $dexfile = "DexFile"
        $loadlib = "System.loadLibrary"
        $runtime_exec = "Runtime.getRuntime"
        $processbuilder = "ProcessBuilder"
        $reflect = "java.lang.reflect"
    condition:
        2 of them
}

rule Android_Privacy_Invasion {
    meta:
        description = "Detects invasive data collection"
    strings:
        $clipboard = "ClipboardManager"
        $contacts = "content://contacts"
        $sms = "content://sms"
        $calllog = "content://call_log"
        $location = "requestLocationUpdates"
        $deviceid = "getDeviceId"
        $imei = "getImei"
        $subscriber = "getSubscriberId"
        $mac = "getMacAddress"
        $serial = "getSerial"
    condition:
        3 of them
}

rule Android_Anti_Analysis {
    meta:
        description = "Detects anti-analysis and anti-debug techniques"
    strings:
        $debugcheck = "isDebuggerConnected"
        $ptrace = "ptrace"
        $emulator1 = "goldfish"
        $emulator2 = "generic"
        $emulator3 = "android_x86"
        $emulator4 = "nox"
        $emulator5 = "bluestacks"
        $frida_check = "frida"
        $xposed = "xposed"
        $substrate = "substrate"
    condition:
        2 of them
}
