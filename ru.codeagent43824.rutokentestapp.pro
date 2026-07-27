TARGET = ru.codeagent43824.rutokentestapp

CONFIG += \
    auroraapp

QT += dbus concurrent network multimedia

PKGCONFIG += \

SOURCES += \
    src/main.cpp \
    src/diagnostics.cpp \
    src/pkcs11_certimport.cpp \
    src/pkcs11_csr.cpp \
    src/pkcs11_errors.cpp \
    src/pkcs11_guard.cpp \
    src/pkcs11_keygen.cpp \
    src/pkcs11_objects.cpp \
    src/pkcs11_tokens.cpp \
    src/tokensession.cpp \
    src/tokenwatcher.cpp \

HEADERS += \
    src/diagnostics.h \
    src/pkcs11_certimport.h \
    src/pkcs11_csr.h \
    src/pkcs11_errors.h \
    src/pkcs11_guard.h \
    src/pkcs11_keygen.h \
    src/pkcs11_minimal.h \
    src/pkcs11_objects.h \
    src/pkcs11_tokens.h \
    src/tokensession.h \
    src/tokenwatcher.h \

DISTFILES += \
    rpm/ru.codeagent43824.rutokentestapp.spec \
    README.md \

# Короткие звуки соединения/рассоединения по NFC (проигрываются через
# QtMultimedia SoundEffect; см. qml/pages/Feedback.qml).
sounds.files = \
    sounds/nfc-connect.wav \
    sounds/nfc-disconnect.wav
sounds.path = /usr/share/$${TARGET}/sounds
INSTALLS += sounds

AURORAAPP_ICONS = 86x86 108x108 128x128 172x172

# The launcher caches icons by resource name.  Keep the application ID stable,
# but install the refined icon under a fresh name referenced by the desktop
# file so an upgrade cannot reuse the pre-1.0.0-6 cached bitmap.
rutoken_icon_86.files = icons/86x86/ru.codeagent43824.rutoken.png
rutoken_icon_86.path = /usr/share/icons/hicolor/86x86/apps
rutoken_icon_108.files = icons/108x108/ru.codeagent43824.rutoken.png
rutoken_icon_108.path = /usr/share/icons/hicolor/108x108/apps
rutoken_icon_128.files = icons/128x128/ru.codeagent43824.rutoken.png
rutoken_icon_128.path = /usr/share/icons/hicolor/128x128/apps
rutoken_icon_172.files = icons/172x172/ru.codeagent43824.rutoken.png
rutoken_icon_172.path = /usr/share/icons/hicolor/172x172/apps
INSTALLS += rutoken_icon_86 rutoken_icon_108 rutoken_icon_128 rutoken_icon_172

CONFIG += auroraapp_i18n

TRANSLATIONS += \
    translations/ru.codeagent43824.rutokentestapp.ts \
    translations/ru.codeagent43824.rutokentestapp-ru.ts \
