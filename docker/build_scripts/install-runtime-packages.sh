#!/bin/bash
# Install packages that will be needed at runtime

# Stop at any error, show all commands
set -exuo pipefail

# Set build environment variables
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Libraries that are allowed as part of the manylinux2014 profile
# Extract from PEP: https://www.python.org/dev/peps/pep-0599/#the-manylinux2014-policy
# On RPM-based systems, they are provided by these packages:
# Package:    Libraries
# glib2:      libglib-2.0.so.0, libgthread-2.0.so.0, libgobject-2.0.so.0
# glibc:      libresolv.so.2, libutil.so.1, libnsl.so.1, librt.so.1, libpthread.so.0, libdl.so.2, libm.so.6, libc.so.6
# libICE:     libICE.so.6
# libX11:     libX11.so.6
# libXext:    libXext.so.6
# libXrender: libXrender.so.1
# libgcc:     libgcc_s.so.1
# libstdc++:  libstdc++.so.6
# mesa:       libGL.so.1
#
# PEP is missing the package for libSM.so.6 for RPM based system

# MANYLINUX_DEPS: Install development packages (except for libgcc which is provided by gcc install)
if [ "${AUDITWHEEL_POLICY}" == "manylinux2010" ] || [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
	MANYLINUX_DEPS="glibc-devel libstdc++-devel glib2-devel libX11-devel libXext-devel libXrender-devel mesa-libGL-devel libICE-devel libSM-devel"
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi

# RUNTIME_DEPS: Runtime dependencies. c.f. install-build-packages.sh
if [ "${AUDITWHEEL_POLICY}" == "manylinux2010" ] || [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
	RUNTIME_DEPS="zlib bzip2 expat ncurses readline tk gdbm libpcap xz openssl keyutils-libs libkadm5 libcom_err libidn libcurl uuid libffi"
	if [ "${AUDITWHEEL_POLICY}" == "manylinux2010" ]; then
		RUNTIME_DEPS="${RUNTIME_DEPS} db4"
	else
		RUNTIME_DEPS="${RUNTIME_DEPS} libdb"
	fi
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi

BASETOOLS="autoconf automake bison bzip2 diffutils file hardlink hostname make patch unzip"
if [ "${AUDITWHEEL_POLICY}" == "manylinux2010" ]; then
	PACKAGE_MANAGER=yum
	BASETOOLS="${BASETOOLS} which"
	# See https://unix.stackexchange.com/questions/41784/can-yum-express-a-preference-for-x86-64-over-i386-packages
	echo "multilib_policy=best" >> /etc/yum.conf
	yum -y update
	yum -y install https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/epel-release-6-8.noarch.rpm curl
	fixup-mirrors
	TOOLCHAIN_DEPS="devtoolset-8-binutils devtoolset-8-gcc devtoolset-8-gcc-c++ devtoolset-8-gcc-gfortran yasm"
	if [ "${AUDITWHEEL_ARCH}" == "x86_64" ]; then
		# Software collection (for devtoolset-8)
		yum -y install centos-release-scl
		fixup-mirrors
	elif [ "${AUDITWHEEL_ARCH}" == "i686" ]; then
		# Add libgfortran4 for devtoolset-7 compat
		TOOLCHAIN_DEPS="${TOOLCHAIN_DEPS} libgfortran4"
		# Install mayeut/devtoolset-8 repo to get devtoolset-8
		curl -fsSLo /etc/yum.repos.d/mayeut-devtoolset-8.repo https://copr.fedorainfracloud.org/coprs/mayeut/devtoolset-8-i386/repo/custom-1/mayeut-devtoolset-8-i386-custom-1.repo
	fi
elif [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
	PACKAGE_MANAGER=yum
	BASETOOLS="${BASETOOLS} which"
	# See https://unix.stackexchange.com/questions/41784/can-yum-express-a-preference-for-x86-64-over-i386-packages
	echo "multilib_policy=best" >> /etc/yum.conf
	# Error out if requested packages do not exist
	echo "skip_missing_names_on_install=False" >> /etc/yum.conf
	# Make sure that locale will not be removed
	sed -i '/^override_install_langs=/d' /etc/yum.conf
	yum -y update
	yum -y install yum-utils curl
	yum-config-manager --enable extras
	TOOLCHAIN_DEPS="devtoolset-9-binutils devtoolset-9-gcc devtoolset-9-gcc-c++ devtoolset-9-gcc-gfortran"
	if [ "${AUDITWHEEL_ARCH}" == "x86_64" ]; then
		# Software collection (for devtoolset-9)
		yum -y install centos-release-scl-rh
		# EPEL support (for yasm)
		yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
		TOOLCHAIN_DEPS="${TOOLCHAIN_DEPS} yasm"
	elif [ "${AUDITWHEEL_ARCH}" == "aarch64" ] || [ "${AUDITWHEEL_ARCH}" == "ppc64le" ] || [ "${AUDITWHEEL_ARCH}" == "s390x" ]; then
		# Software collection (for devtoolset-9)
		yum -y install centos-release-scl-rh
	elif [ "${AUDITWHEEL_ARCH}" == "i686" ]; then
		# No yasm on i686
		# Install mayeut/devtoolset-9 repo to get devtoolset-9
		curl -fsSLo /etc/yum.repos.d/mayeut-devtoolset-9.repo https://copr.fedorainfracloud.org/coprs/mayeut/devtoolset-9/repo/custom-1/mayeut-devtoolset-9-custom-1.repo
	fi
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi

if ! which localedef &> /dev/null; then
	# somebody messed up glibc-common package to squeeze image size, reinstall the package
	if [ ${PACKAGE_MANAGER} == yum ]; then
		yum -y reinstall glibc-common
	else
		echo "Not implemented"
		exit 1
	fi
fi

# upgrading glibc-common can end with removal on en_US.UTF-8 locale
localedef -i en_US -f UTF-8 en_US.UTF-8

if [ ${PACKAGE_MANAGER} == yum ]; then
	yum -y install ${BASETOOLS} ${TOOLCHAIN_DEPS} ${MANYLINUX_DEPS} ${RUNTIME_DEPS}
	yum clean all
	rm -rf /var/cache/yum
else
	echo "Not implemented"
	exit 1
fi


# Fix libc headers to remain compatible with C99 compilers.
find /usr/include/ -type f -exec sed -i 's/\bextern _*inline_*\b/extern __inline __attribute__ ((__gnu_inline__))/g' {} +

if [ "${DEVTOOLSET_ROOTPATH:-}" != "" ]; then
	# remove useless things that have been installed by devtoolset
	rm -rf $DEVTOOLSET_ROOTPATH/usr/share/man
	find $DEVTOOLSET_ROOTPATH/usr/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
fi

rm -rf /usr/share/backgrounds

# if we updated glibc, we need to strip locales again...
if localedef --list-archive | grep -sq -v -i ^en_US.utf8; then
	localedef --list-archive | grep -v -i ^en_US.utf8 | xargs localedef --delete-from-archive
fi
if [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
	mv -f /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
	build-locale-archive
fi

find /usr/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
if [ -d /usr/local/share/locale ]; then
	find /usr/local/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
fi
if [ -d /usr/local/share/man ]; then
	rm -rf /usr/local/share/man
fi
