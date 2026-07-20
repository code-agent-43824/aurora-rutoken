TARGET = ru.codeagent43824.rutokentestapp

CONFIG += \
    auroraapp

QT += dbus concurrent

PKGCONFIG += \

SOURCES += \
    src/main.cpp \
    src/diagnostics.cpp \
    src/pkcs11_tokens.cpp \
    src/tokenwatcher.cpp \

HEADERS += \
    src/diagnostics.h \
    src/pkcs11_minimal.h \
    src/pkcs11_tokens.h \
    src/tokenwatcher.h \

DISTFILES += \
    rpm/ru.codeagent43824.rutokentestapp.spec \
    README.md \

AURORAAPP_ICONS = 86x86 108x108 128x128 172x172

CONFIG += auroraapp_i18n

TRANSLATIONS += \
    translations/ru.codeagent43824.rutokentestapp.ts \
    translations/ru.codeagent43824.rutokentestapp-ru.ts \
