# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A test application supporting Rutoken devices (hardware cryptographic tokens by Aktiv Company) on Aurora OS (a Russian mobile operating system derived from Sailfish OS).

## Current State

This is a greenfield repository: it contains only the README and MIT license. There is no source code, build system, test suite, or CI configuration yet.

Once the initial application is implemented, update this file with:

- Build, run, and test commands (including how to run a single test)
- High-level architecture of the application

## Domain Context

These are general platform facts, not choices this repository has made yet:

- Aurora OS applications are typically built with Qt/QML against the Aurora SDK and packaged as RPMs (`.spec` file, `.pro` qmake project or CMake).
- Rutoken devices are typically accessed through the PKCS#11 interface (Aktiv's rtPKCS11ECP library); on mobile devices they connect over USB or NFC.
