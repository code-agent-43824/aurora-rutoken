Name:       ru.codeagent43824.rutokentestapp
Summary:    Rutoken ECP 3.0 test application
Version:    0.0.3
Release:    2
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

%description
Test application for working with Rutoken ECP 3.0 hardware tokens over USB
and NFC on Aurora OS. Version 0.0.3 dynamically loads the official Rutoken
PKCS#11 module and verifies its lifecycle and C_GetInfo metadata, in addition
to PC/SC and NFC reachability diagnostics.

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
* Sun Jul 19 2026 Watson <noreply@openclaw.ai> - 0.0.3-1
- Add dynamic Rutoken PKCS#11 lifecycle and library information diagnostics.

* Sun Jul 19 2026 Watson <noreply@openclaw.ai> - 0.0.2-2
- Rebuild each architecture in an isolated CI job and verify RPM/ELF metadata.
