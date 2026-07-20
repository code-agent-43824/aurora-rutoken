Name:       ru.codeagent43824.rutokentestapp
Summary:    Rutoken ECP 3.0 test application
Version:    0.4.0
Release:    1
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

%description
Test application for working with Rutoken ECP 3.0 hardware tokens over USB
and NFC on Aurora OS. Version 0.4 adds certificate export (DER and PEM, without
the private key), and will add key-pair generation and certificate import.
Builds on the v0.3 two-level object browser (certificates described from the
parsed X.509 body, keys nested by CKA_ID).

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
