Name:       ru.codeagent43824.rutokentestapp
Summary:    Rutoken ECP 3.0 test application
Version:    1.2.0
Release:    8
Group:      Qt/Qt
License:    MIT
URL:        https://github.com/code-agent-43824/aurora-rutoken
Source0:    %{name}-%{version}.tar.bz2

Requires:   sailfishsilica-qt5 >= 0.10.9
BuildRequires:  pkgconfig(auroraapp)
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5DBus)
BuildRequires:  pkgconfig(Qt5Concurrent)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  pkgconfig(Qt5Multimedia)

%description
Test application for working with Rutoken ECP 3.0 devices over USB and NFC on
Aurora OS. It shows connected devices, logs in with the user PIN
(numeric pad), browses objects, generates key pairs (GOST R 34.10-2012 and
RSA), imports and exports certificates, and manages PINs (change user/admin
PIN, unblock the user PIN). NFC uses a guided connect wizard; the certificate
is auto-attached to its key pair by public key on import. Files can be signed
as detached or attached CMS/PKCS#7 with a certificate and private key stored
on the Rutoken.
When explicitly enabled in Settings, an independently installed CryptoPro CSP
adds read-only certificates and linked keys to the same per-device object list
through the runtime-loaded CapiLite API. PKCS#11 objects take precedence over
exact duplicates. CryptoPro CSP is not bundled or required.

%prep
%autosetup

%build
%qmake5
%make_build

%install
%make_install

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%defattr(644,root,root,-)
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Thu Jul 30 2026 Claude <noreply@anthropic.com> - 1.2.0-8
- Bring the CryptoPro view to the NFC path: the container scan now runs inside
  the same hold, right after the PKCS#11 read, and its result is kept as a
  snapshot next to the NFC object snapshot, so CryptoPro objects stay visible
  after the device is taken away. Avoid needless CAPI passes — reading through
  CryptoPro is much slower than PKCS#11 — by scanning only when the set of
  readers changes and at least one device is present; losing a device keeps the
  last snapshot, and NFC write operations do not trigger a scan. An object found
  through both interfaces now reports "PKCS#11 and CryptoPro CSP". Show the
  CryptoPro version once instead of twice and extend it with the build number
  discovered in the installed package metadata.

* Thu Jul 30 2026 Claude <noreply@anthropic.com> - 1.2.0-7
- Stop listing a CryptoPro key container separately when its key belongs to a
  certificate that is already shown: the container public key is exported and
  matched against the public key of every displayed certificate from both
  backends (GOST byte order handled), so the key appears only as a child of its
  certificate. Show the container path on the certificate screen as well, not
  only in the object list. Report the CryptoPro CSP version (provider version
  plus the installed package version when available) in diagnostics instead of
  only the library file.

* Thu Jul 30 2026 Claude <noreply@anthropic.com> - 1.2.0-6
- Read the certificate stored inside a CryptoPro container instead of relying on
  the registered-certificate store: enumerating the system store only returns
  installed certificates, which this application never registers, so a container
  holding its own certificate looked empty. The container context is now opened
  silently and the certificate bound to its key is read through KP_CERTIFICATE.
  Show the certificate Common Name as the card title and move the container name
  and path to the metadata line used for CKA_LABEL/CKA_ID. Widen CryptoPro
  runtime library detection to modules outside the known directories.

* Thu Jul 30 2026 Watson <noreply@openai.com> - 1.2.0-5
- Show CryptoPro-only containers even when PKCS#11 object enumeration is empty
  or fails. Report every CryptoPro shared library loaded by the CAPI helper.

* Thu Jul 30 2026 Watson <noreply@openai.com> - 1.2.0-4
- Replace periodic token enumeration with blocking C_WaitForSlotEvent. Make
  CryptoPro opt-in, diagnose it conditionally and merge non-duplicate CAPI
  certificates into the per-device PKCS#11 object list.

* Thu Jul 30 2026 Watson <noreply@openai.com> - 1.2.0-3
- Isolate read-only CapiLite scans in a bounded helper process so a CSP crash
  cannot terminate the UI. Group provider aliases of one physical container.

* Thu Jul 30 2026 Watson <noreply@openai.com> - 1.2.0-2
- Load CapiLite from the CryptoPro CSP Aurora sandbox package and grant the
  application access to the CSP D-Bus service. Keep CSP optional and read-only.

* Thu Jul 30 2026 Watson <noreply@openai.com> - 1.2.0-1
- Add an optional read-only CryptoPro CapiLite view. Detect libcapi20 at
  runtime, enumerate Rutoken containers and linked certificates through
  CryptoAPI, show key availability and certificate/container consistency
  diagnostics. Do not bundle CSP and do not affect the existing PKCS#11 path.

* Thu Jul 30 2026 Watson <noreply@openai.com> - 1.1.0-2
- Speed up CMS signing by using the PKCS#11 library hashing path. Sort expired
  certificates last, render them inactive and prevent signing with them.

* Tue Jul 28 2026 Watson <noreply@openai.com> - 1.1.0-1
- Add detached (.p7s) and attached (.p7m) CMS file signing through the
  official Rutoken C_EX_PKCS7Sign extension. Select the exact certificate,
  source file, output directory and name; support both USB and NFC PIN flows
  and never overwrite an existing result.

* Mon Jul 27 2026 Watson <noreply@openai.com> - 1.0.0-7
- Restore the package-name icon identifier required by Aurora RPM validation.
  Keep the refined Slim-C artwork and reject noncanonical launcher icon names
  in CI.

* Mon Jul 27 2026 Watson <noreply@openai.com> - 1.0.0-6
- Refine the Slim-C launcher silhouette: a larger lanyard hole, a clearer
  taper next to the connector and a short flat Type-C blade. Install the icon
  under a fresh resource name so Aurora Launcher does not reuse its old cache.

* Mon Jul 27 2026 Watson <noreply@openai.com> - 1.0.0-5
- Rename the launcher from "Rutoken Test" to "Rutoken" and replace the generic
  USB-device icon with an abstract silhouette of the Rutoken ECP 3.0 NFC
  Slim-C: slim body, lanyard hole, tapered shoulder, USB Type-C connector and
  NFC waves.

* Sun Jul 26 2026 Watson <noreply@openai.com> - 1.0.0-4
- Final v1.0 polish: keep the login action on the Objects view until
  authentication, but remove the redundant logout button, remembered-PIN status
  and green login-success result. A failed login remains visible in red.

* Sun Jul 26 2026 Watson <noreply@openai.com> - 1.0.0-3
- Use "device" or "Rutoken" instead of the physical-form-specific "token" in
  user-facing text: NFC products may be USB devices, smart cards, key fobs or
  rings. The built-in NFC animation now labels the product «Рутокен» in Russian.

* Sun Jul 26 2026 Watson <noreply@openai.com> - 1.0.0-2
- Move USB login controls from Properties to Objects, where authentication is
  relevant for displaying private keys. Add the same login action for an NFC
  snapshot connected without a PIN: the existing NFC wizard now requires the PIN,
  re-reads the token during one hold and returns to the open Objects view.

* Sat Jul 25 2026 Claude <noreply@anthropic.com> - 1.0.0-1
- Release 1.0. Move the token administration actions (change user/admin PIN,
  unblock the user PIN, change the label) from visible buttons on the Properties
  view into the top pull-down menu, which is now context-sensitive: the
  Properties view offers the administration items and the Objects view offers
  "Import certificate" / "Generate key pair". Finalized the documentation for the
  1.0 milestone and removed stale translation entries left over from earlier
  refactors. Feature set: live USB/NFC token list, PIN login, object browser,
  GOST R 34.10-2012 and RSA key generation, certificate import/export, PIN
  management, object deletion and PKCS#10 certificate requests — all over USB and
  NFC, verified on an Aurora 5.2 armv7hl device.

* Fri Jul 24 2026 Claude <noreply@anthropic.com> - 0.9.0-3
- Reworked the main token flow: tapping a token now opens a single page with a
  view switcher at the top — "Properties" (default: token details, PIN login and
  the administration actions — change user/admin PIN, unblock, change label) and
  "Objects" (certificates and keys with their actions — generate, import, export,
  delete, certificate request). Both views are one tap apart; the separate
  "Objects" button on the token card is gone. TokenDetailsPage and ObjectsPage were
  merged into TokenPage.

* Thu Jul 23 2026 Claude <noreply@anthropic.com> - 0.9.0-2
- Polish: when the Rutoken PKCS#11 library is not installed, the status and every
  operation now tell the user to install the official ru.rutoken.librtpkcs11ecp
  package (it ships as a separate RPM next to the app) instead of just saying the
  library is missing. The application version is also shown at the bottom of the
  main screen, not only on the diagnostics page.

* Thu Jul 23 2026 Claude <noreply@anthropic.com> - 0.9.0-1
- Stabilization, NFC/token-removal recovery: when the token is removed too early
  or becomes unavailable during an operation, the message now tells you what to do
  (e.g. "токен убран во время операции — повторите, удерживая токен на связи",
  "токен не подключён — подключите токен и повторите", "сессия прервана (возможно,
  токен убран) — повторите") instead of a bare code. The NFC connect / generate /
  import / CSR wizard gained a "Try again" button on failure that re-detects the
  token and re-runs the same operation with the already-entered PIN, no re-typing
  — matching the "Start over" the PIN-change / label / delete NFC flows already had.

* Thu Jul 23 2026 Claude <noreply@anthropic.com> - 0.8.0-1
- Human-readable PKCS#11 error messages: failures used to show only a raw hex code
  (e.g. "C_Sign: 0x00000070"); a central mapping now turns the CKR_* code into a
  Russian explanation with the code kept for diagnostics (e.g. "неверный механизм
  (0x00000070)", "нужен вход по PIN-коду (0x00000101)", "недостаточно памяти на
  токене"). Wired across key generation, certificate import, CSR, deletion, PIN
  operations and session/login errors (new pkcs11_errors module; the duplicated
  local hex helpers were removed). The GOST-256 and GOST-512 certificate requests
  from v0.7 were verified on a PC with the openssl GOST engine (both "verify OK").

* Thu Jul 23 2026 Claude <noreply@anthropic.com> - 0.7.0-2
- Certificate request (CSR) over NFC: the CSR screen now works with an NFC token
  too — fill in the DN, then a guided hold (take the token, enter the PIN, hold it
  once) signs the request and the PEM is shown back on the CSR screen to save. The
  NFC connect wizard gained a "csr" operation carrying the key id and DN. The
  GOST-256 CSR from 0.7.0-1 was verified on a PC with the openssl GOST engine
  ("Certificate request self-signature verify OK"), so the DER/GOST encoding is
  confirmed correct; no byte-order change was needed.

* Thu Jul 23 2026 Claude <noreply@anthropic.com> - 0.7.0-1
- Certificate request (PKCS#10 / CSR) for a key pair on the token (USB): fill in
  the subject DN (CN required, O/OU/C/L/ST/email optional), the request is built
  and signed by the private key on the token, and the resulting PEM is shown and
  can be saved to a .csr file. Reachable by tapping a key on the objects screen or
  from the certificate card pull-down. The signature reuses the wired C_Sign with
  the GOST "sign-with-hash" mechanism (CKM_GOSTR3410_WITH_GOSTR3411_12_256/512) or
  SHA256-RSA; the SubjectPublicKeyInfo is read from the token (CKA_VALUE + GOST
  params). New DER encoder builds the request (pkcs11_csr). GOST byte order follows
  RFC 4491/9215 and is to be verified on device with an openssl GOST engine. CSR
  over NFC and any byte-order corrections come next.

* Thu Jul 23 2026 Claude <noreply@anthropic.com> - 0.6.0-7
- After creating an object the app now returns to the objects list instead of
  staying on the creation form: generating a key pair or importing a certificate
  pops back to the list on success (USB right after the operation, NFC once the
  hold wizard reports success via a new finishedOk signal), and the result — the
  test-signature outcome included — is shown on the list. Fixed a UX rule the
  owner asked to apply everywhere; recorded it in AGENTS.md.

* Thu Jul 23 2026 Claude <noreply@anthropic.com> - 0.6.0-6
- Test signature right after generating a key pair: sign a fixed buffer with the
  new private key and verify it with the new public key in the same session, so
  the result confirms the pair actually works. The mechanism follows the key type
  (GOST 2012-256 -> CKM_GOSTR3410 over 32 bytes, GOST 2012-512 -> CKM_GOSTR3410_512
  over 64 bytes, RSA -> CKM_RSA_PKCS); the outcome is appended to the generation
  message. C_SignInit (#43), C_Sign (#44), C_VerifyInit (#49) and C_Verify (#50)
  were wired into the function-list ABI from placeholders with offset static_asserts.
  Generated keys now carry CKA_SIGN / CKA_VERIFY so they are usable for signing.

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.6.0-5
- Delete objects over NFC. Press and hold an object (or use the "Delete
  certificate" pull-down in the certificate card) on the NFC token: for a
  certificate you first choose the scope (only the certificate / certificate and
  its keys), then enter the PIN, then hold the token once to run the whole delete
  in a single session (login, C_DestroyObject by CKA_ID, re-read). Keys are
  removed straight after the PIN, no scope question. The NFC object snapshot is
  refreshed on success so the list reflects the deletion without holding again
  (new NfcDeletePage, modelled on the NFC PIN-change flow).

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.6.0-4
- Fix the NFC "Continue without PIN" connect that hung forever: a no-login read
  (preview) leaves outcome at 0, so the wizard never advanced — it now finishes on
  the no-PIN path by watching busy instead of the outcome. Add a "Delete only the
  certificate" button to the not-logged-in delete screen: it removes just the
  public certificate object without a login (new TokenSession::deleteCertPublic —
  R/W session, no C_Login, destroy the CKO_CERTIFICATE by CKA_ID); any key stays
  since it is invisible without the PIN.

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.6.0-3
- When deleting a certificate while not logged in, the chooser now warns that the
  certificate may have a private key hidden until the PIN is entered and offers an
  "Enter PIN" button (the key option appears once you log in). The NFC connect step
  gained a "Continue without PIN" button that reads only the public certificates
  without logging in. Unified all Russian wording to a single spelling, "PIN-код"
  (previously mixed "PIN" / "Пин" / "пин"), across the UI strings and the result
  messages.

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.6.0-2
- After connecting an NFC token the wizard now opens the token properties screen
  (like USB) instead of jumping straight to the certificates; the objects were
  already read during the connect, so they open from the details without holding
  the token again. Deleting a certificate now always asks whether to remove only
  the certificate or the certificate together with its keys (new DeleteCertPage),
  and a "Delete certificate" item was added to the certificate card's pull-down
  menu in addition to the long-press on the objects list.

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.6.0-1
- Delete objects from the token (USB): press and hold a certificate or a key on
  the objects screen to remove it together with its key pair (everything sharing
  the CKA_ID), with a RemorsePopup countdown to cancel. C_DestroyObject (#23) was
  wired into the function-list ABI with an offset static_assert; the object list
  refreshes right after in the same logged-in session. Deletion over NFC and a
  post-generation test signature come next.

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.5.0-7
- Manage the NFC token from its own overview, like USB: tapping the connected
  NFC token now opens the token details with the same pull-down menu (change
  user / admin PIN, unblock, change label) instead of a separate card. The
  operations run over NFC (collect the data, then one hold). The extra "Manage
  PIN over NFC" card was removed, so there is a single virtual NFC token. Also:
  drop the "can lock the token" warning that flashed before the PIN screens, and
  show the real application version in the diagnostics header.

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.5.0-6
- PIN operations over NFC: change the user PIN, change the admin PIN and unblock
  the user PIN with the token held only once. A new "Manage PIN over NFC" entry
  in the NFC section opens a chooser; the same entry screens collect every PIN
  first (no token needed), then a single hold to the back cover runs the whole
  operation in one session. On failure "Start over" re-collects. PinChangePage
  gained a connection property (USB unchanged; NFC adds the hold/animation via
  the existing NfcHoldAnimation and token detection, like the connect wizard).

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.5.0-5
- PIN change now flows straight through the entry screens without ever returning
  to the operation's base screen between steps and without a summary of entered
  PINs. Tapping the menu item goes right to the current-PIN pad, then the new PIN,
  then repeat it; as soon as the repeat is entered the operation runs (if the two
  new PINs match, otherwise it asks for them again). Unblock is a single admin-PIN
  screen, then the reset runs. PinPadPage gained an autoPop flag so the controller
  drives the chain (replace between steps, one pad above it) with no push/pop race.

* Wed Jul 22 2026 Claude <noreply@anthropic.com> - 0.5.0-4
- PIN change (user / admin / unblock) is now collected as a sequence of screens:
  opening the operation asks for each PIN on its own numeric pad in turn (current
  -> new -> confirm), then shows a summary with the apply button. Re-read the
  token label after changing it: the token-set signature now includes the label
  and the details/list refresh, so the new label shows up immediately instead of
  the old one.

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.5.0-3
- Unblock the user PIN through the Rutoken vendor call C_EX_UnblockUserPIN
  (administrator/SO login, then reset the user PIN attempt counter) instead of
  C_InitPIN — the user PIN itself is kept, only the zeroed attempt counter is
  restored. Change the token label with a USER login (C_EX_SetTokenName needs the
  user, not the SO, so it no longer fails with CKR_USER_NOT_LOGGED_IN / 101).

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.5.0-2
- Fix the user PIN change (Rutoken requires a USER login before C_SetPIN; it was
  failing with CKR_USER_NOT_LOGGED_IN). Show the honest number of remaining PIN
  attempts (Rutoken C_EX_GetTokenInfoExtended) instead of a "few / last attempt"
  hint. Add "Change token label" (C_EX_SetTokenName, administrator PIN) to the
  token details pull-down menu.

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.5.0-1
- PIN management: change the user PIN (C_SetPIN), change the administrator (SO)
  PIN, and unblock the user PIN with the administrator PIN (C_Login as SO +
  C_InitPIN). Reachable from the token details pull-down menu; PINs are entered
  on the numeric pad with confirmation of the new PIN. C_InitPIN (#11) and
  C_SetPIN (#12) offsets were verified against the real library.

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.4.1-4
- Hide the "Connect over NFC" entry while an NFC token is already connected
  (one at a time). Play the connect/disconnect sounds from bundled WAV files
  via QtMultimedia (Nemo.Ngf was silent on the device). Show an empty title
  instead of the "(no label)" placeholder for objects without a label.

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.4.1-3
- A connected NFC token now stays in the list as a logical connection: its
  objects snapshot is kept so you can re-open its certificates without holding
  the token again. Every token has a small "Disconnect" button — for NFC it is
  forgotten, for USB it is hidden until physically reconnected. The NFC hold
  animation now reacts to detection (token stuck to the back while working, then
  moved away when done), with best-effort system sounds on connect/disconnect.

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.4.1-2
- NFC connection paradigm: the main screen lists USB tokens live and shows an
  ephemeral "Connect over NFC" entry. Tapping it runs a wizard — take the token,
  enter the PIN, hold it to the back cover (with a built-in animation and
  progress), remove it. Key generation and certificate import over NFC run
  through the same wizard; the NFC PIN is never remembered. Also fixes the PIN
  pad so the show/hide button no longer shifts the keypad.

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.4.1-1
- PIN entry moved to a dedicated screen with a numeric keypad and a switch to
  the OS text keyboard. For USB the PIN is remembered in memory after the first
  successful login (reused by key generation and certificate import without
  re-typing) until you log out, unplug the USB token, or close the app; a
  "Log out" button clears it. (NFC connection wizard follows in 0.4.1-2.)

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.4.0-5
- Import an X.509 certificate from a file (PEM or DER) onto the token via
  C_CreateObject, reachable from the Objects screen pull-down menu. The
  certificate is auto-attached to its key pair by matching the public key
  (its CKA_ID is copied); only the certificate is written, never a private key.

* Tue Jul 21 2026 Claude <noreply@anthropic.com> - 0.4.0-4
- Generate a key pair on the token: choose the algorithm and length (GOST R
  34.10-2012 256/512, RSA 2048/4096), enter the user PIN. Reachable from the
  Objects screen pull-down menu; the object list refreshes after generation.

* Mon Jul 20 2026 Claude <noreply@anthropic.com> - 0.4.0-3
- Show CKA_ID as text when its first bytes are printable ASCII (non-printable
  bytes shown as "."), otherwise hex.

* Mon Jul 20 2026 Claude <noreply@anthropic.com> - 0.4.0-2
- Certificate detail screen (tap a certificate); export moved to its pull-down
  menu with a chosen format (PEM or DER), file name and folder.

* Mon Jul 20 2026 Claude <noreply@anthropic.com> - 0.4.0-1
- Export a certificate to DER and PEM files (no private key); UserDirs
  permission. Restore per-arch Actions artifacts as a second download channel.

* Mon Jul 20 2026 Claude <noreply@anthropic.com> - 0.3.0-2
- Show certificates before PIN login (public objects); parse the X.509 body
  for Common Name, issuer and expiry instead of CKA_ID/CKA_LABEL.

* Mon Jul 20 2026 Claude <noreply@anthropic.com> - 0.3.0-1
- Two-level object browser: certificates with nested keys grouped by CKA_ID,
  standalone keys on the top level, read source labelled (PKCS#11).

* Mon Jul 20 2026 Claude <noreply@anthropic.com> - 0.2.0-1
- Token details screen with user PIN login (C_Login) and remaining-attempts
  indicator; shared PKCS#11 mutex so polling and login do not overlap.

* Mon Jul 20 2026 Claude <noreply@anthropic.com> - 0.1.0-1
- First product screen: live list of connected tokens (USB/NFC) that
  updates automatically; diagnostics moved to a separate page.

* Mon Jul 20 2026 Claude <noreply@anthropic.com> - 0.0.4-1
- Enumerate connected tokens (USB and NFC): label, serial, model, connection type.

* Sun Jul 19 2026 Watson <noreply@openclaw.ai> - 0.0.3-2
- Fix PKCS#11 struct ABI (drop Windows pack(1)) that crashed the app on device.

* Sun Jul 19 2026 Watson <noreply@openclaw.ai> - 0.0.3-1
- Add dynamic Rutoken PKCS#11 lifecycle and library information diagnostics.

* Sun Jul 19 2026 Watson <noreply@openclaw.ai> - 0.0.2-2
- Rebuild each architecture in an isolated CI job and verify RPM/ELF metadata.
