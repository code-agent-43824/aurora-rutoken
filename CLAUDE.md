# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A test application for Aurora OS (Russian mobile OS derived from Sailfish OS) that works with Rutoken ECP 3.0 hardware cryptographic tokens over both USB and NFC.

**Chosen stack (decided 2026-07-19, rationale in `docs/RESEARCH.md` §4):** native Qt/C++ with QML UI, qmake project, RPM packaging via the Aurora SDK. Token access path: PKCS#11 (`librtpkcs11ecp.so` by Aktiv) → `libpcsclite` → `pcscd`; USB tokens are served by the CCID handler, NFC tokens by the OS NFC stack (`nfcd`) exposed as another PC/SC reader. Flutter was evaluated and rejected (no PC/SC/PKCS#11 plugins for Aurora; a C++ bridge would be required anyway).

## MANDATORY agent workflow

This project is developed by coding agents working in relay. Any agent can be interrupted at any moment; the next agent must be able to continue from repository state alone. Therefore:

1. **Before doing anything**: read `PLAN.md` (current state, next tasks) and the top entries of `docs/JOURNAL.md`.
2. **Plan first**: record the intended action as a task in `PLAN.md` **before** performing it.
3. **Act, then record**: mark the task `[x]` in `PLAN.md` (with date) and add an entry to `docs/JOURNAL.md` — what was done, why, and commit hashes. Commit these updates together with (or immediately after) the work itself.
4. Update `docs/RESEARCH.md` whenever new facts about Aurora/Rutoken are established (with sources).

## Git rules (set by the project owner — do not deviate)

- **No branches, ever.** All work is committed directly to `main` (the repository's default branch; the owner calls it "master") and pushed to `origin main` immediately after each completed change.
- Do not create pull requests. Do not create feature branches. If a stray branch appears, merge anything valuable into `main` and delete the branch (local and remote).
- Push with `git push origin main`; on network failure retry with exponential backoff.

## Project documentation (in Russian)

- `PLAN.md` — staged plan with task checkboxes and statuses; open questions for the owner at the bottom.
- `docs/JOURNAL.md` — chronological log of what was done, why, with commit hashes (newest on top).
- `docs/RESEARCH.md` — research findings: Aurora ecosystem, how Rutoken works on Aurora, framework decision, sources.

## Key external references

- Aurora OS examples on Mos.Hub (OMP's group): https://hub.mos.ru/auroraos — most relevant: `demos/ApplicationTemplate` (app skeleton), `demos/NfcUseCases` (pcsc-lite + nfcd via D-Bus), `demos/UsbUseCases` (libusb).
- Aurora developer portal: https://developer.auroraos.ru (docs, demo catalogue, Flutter docs).
- Rutoken PKCS#11 library downloads (Aurora ARM32/ARM64 RPMs): https://www.rutoken.ru/support/download/pkcs/
- Rutoken SDK: https://www.rutoken.ru/developers/sdk/ and docs portal: https://dev.rutoken.ru

## Build commands

Not available yet — the application skeleton is Stage 1 in `PLAN.md`. As soon as the skeleton lands, document here: how to build the RPM with the Aurora SDK, how to run on the emulator/device, and how to run tests.

## Current state

Stage 0 (research, stack decision, documentation) is complete. Next: Stage 1 (application skeleton); answers to the open questions at the bottom of `PLAN.md` are wanted first.
