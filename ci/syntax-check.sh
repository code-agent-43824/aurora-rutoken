#!/bin/sh
# Локальная проверка компилируемости C++ ДО пуша.
#
# Зачем: собирает проект только CI в Аврора PSDK, и цикл «пуш → 5 минут → узнал
# об опечатке» дорогой. Сборка 1.3.0-19 упала на одной необъявленной переменной
# (run #101), которую эта проверка ловит за секунды.
#
# Проверяется ТОЛЬКО синтаксис и типы (-fsyntax-only) обычным g++ с системными
# заголовками Qt5. Это не замена сборке: целевая система — Аврора с Qt 5.6 на
# armv7hl, здесь же Qt новее, поэтому предупреждения о deprecated ожидаемы и
# игнорируются, а сверяются только ошибки.
#
# src/main.cpp пропускается: ему нужен auroraapp.h, которого вне PSDK нет.
set -eu

QT_INCLUDE=""
for candidate in /usr/include/x86_64-linux-gnu/qt5 /usr/include/aarch64-linux-gnu/qt5 \
                 /usr/include/qt5; do
    if [ -d "$candidate/QtCore" ]; then
        QT_INCLUDE="$candidate"
        break
    fi
done

if [ -z "$QT_INCLUDE" ]; then
    echo "Qt5 headers not found - skipping the local syntax check" >&2
    exit 0
fi

status=0
for source in src/*.cpp; do
    case "$source" in
        src/main.cpp) continue ;;
    esac
    errors=$(g++ -fsyntax-only -std=c++11 -fPIC -I. \
        -isystem "$QT_INCLUDE" \
        -isystem "$QT_INCLUDE/QtCore" \
        -isystem "$QT_INCLUDE/QtNetwork" \
        -isystem "$QT_INCLUDE/QtGui" \
        -isystem "$QT_INCLUDE/QtQml" \
        -isystem "$QT_INCLUDE/QtQuick" \
        -isystem "$QT_INCLUDE/QtDBus" \
        -isystem "$QT_INCLUDE/QtConcurrent" \
        "$source" 2>&1 | grep -E "error:" || true)
    if [ -n "$errors" ]; then
        echo "$source:" >&2
        echo "$errors" >&2
        status=1
    fi
done

if [ "$status" -ne 0 ]; then
    echo "Syntax check failed - fix before pushing" >&2
    exit 1
fi

echo "Syntax check passed for src/*.cpp (except main.cpp, which needs the PSDK)"
