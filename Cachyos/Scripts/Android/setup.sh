#!/usr/bin/env bash
LC_ALL=C LANG=C

adb shell pm grant moe.shizuku.privileged.api android.permission.WRITE_SECURE_SETTINGS
