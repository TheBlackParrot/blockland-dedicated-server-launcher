#!/bin/bash

NO_SCREEN=false
ATTACH=false
GAMEMODE="Custom"
export WINEDLLOVERRIDES="mscoree=d;mshtml=d;$WINEDLLOVERRIDES"
DEDICATED_MODE="-dedicated"

INSTALLING=false
BE_QUIET=false

BLOCKLAND_FILES_DL_FILENAME="BLr1988-server.zip"
BLOCKLAND_FILES_DL_URL="https://birb.zone/files/$BLOCKLAND_FILES_DL_FILENAME"

if [ $(id -u) -eq 0 ]; then
	echo "This script cannot be run as root"
	exit 1
fi

qread() {
	if $BE_QUIET; then
		echo "$*"
	else
		read -n 1 -s -r -p "$*"
	fi
}

motd() {
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo "!!!!! THIS SCRIPT IS NOT GUARANTEED TO WORK FOR YOUR SYSTEM !!!!!"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo -e "If it fails, please send the output of 'cat /etc/os-release' to TheBlackParrot#1352 on Discord.\n"	
}

sudo_check() {
	if [ ! -x $(which sudo) ]; then
		echo -e "Please install sudo.\n"
		exit 1
	fi	
}

override_check() {
	if [ ! -z "$USE_FILE_FOR_BL_DATA" ]; then
		if [ ! -e "$USE_FILE_FOR_BL_DATA" ]; then
			echo "Cannot access $USE_FILE_FOR_BL_DATA, please check permissions and/or if the file exists."
			exit 1
		fi
	fi
}

create_install_dir() {
	if [ ! -d "$INSTALL_DIR" ]; then
		if mkdir "$INSTALL_DIR"; then
			echo "Created directory $INSTALL_DIR"
		else
			echo "Failed to create installation directory."
			exit 1
		fi
	fi
}

gather_and_unpack_blockland() {
	if [ -z "$USE_FILE_FOR_BL_DATA" ]; then
		echo "not using an overriding local file"
		if [ ! -e $BLOCKLAND_FILES_DL_FILENAME ]; then
			qread "Blockland must now be downloaded, press any key to continue."

			if which wget; then
				echo "wget is reachable, using it"
				wget $BLOCKLAND_FILES_DL_URL
			else
				echo "wget isn't reachable, attempting curl"
				curl -o $BLOCKLAND_FILES_DL_FILENAME $BLOCKLAND_FILES_DL_URL
			fi

			if [ ! -e $BLOCKLAND_FILES_DL_FILENAME ]; then
				echo "Failed to download server files, aborting."
				exit 1
			fi
		fi
		unzip $BLOCKLAND_FILES_DL_FILENAME
	else
		unzip "$USE_FILE_FOR_BL_DATA" -d $INSTALL_DIR
	fi

	if [ ! -e "$INSTALL_DIR/Blockland.exe" ]; then
		echo "Blockland.exe not present in install directory! (Tried to install to $INSTALL_DIR)"
	fi
}

enable_repo_arch() {
	if grep -Fx "[multilib]" /etc/pacman.conf; then
		echo "Multilib repository already enabled."
	else
		qread "The multilib repository needs to be enabled, press any key to continue."
		echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf > /dev/null
	fi

	yes | sudo pacman --noconfirm -Syy	
}

enable_repo_fedora() {
	if [ ! -e /etc/yum.repos.d/winehq.repo ]; then
		qread "The WineHQ repository needs to be enabled, press any key to continue."

		if [ $VERSION_ID -eq 29 ]; then
			VERSION_ID=28
		fi
		sudo dnf --assumeyes config-manager --add-repo https://dl.winehq.org/wine-builds/fedora/$VERSION_ID/winehq.repo
	else
		echo "WineHQ repository already enabled."
	fi
}

enable_repo_ubuntu() {
	case "$VERSION_ID" in
		14.04|14.10|15.04|15.10|16.04|16.10|17.04|17.10|18.04)
			if grep "^deb https://dl.winehq.org/wine-builds/ubuntu" /etc/apt/sources.list; then
				echo "WineHQ repository already enabled"
			else
				qread "The WineHQ repository needs to be enabled, press any key to continue."

				sudo dpkg --add-architecture i386

				if which wget; then
					wget -O /tmp/Release.key https://dl.winehq.org/wine-builds/Release.key
				else
					curl -o /tmp/Release.key https://dl.winehq.org/wine-builds/Release.key
				fi
				sudo apt-key add /tmp/Release.key
				rm /tmp/Release.key

				sudo apt-add-repository https://dl.winehq.org/wine-builds/ubuntu/
			fi
			sudo apt-get update
			;;

		*)
			echo "This version of Ubuntu is not supported."
			exit 1
			;;
	esac
}

enable_repo_debian() {
	case "$VERSION_ID" in
		7|8|9)
			if grep "^deb https://dl.winehq.org/wine-builds/debian" /etc/apt/sources.list; then
				echo "WineHQ repository already enabled"
			else
				qread "The WineHQ repository needs to be enabled, press any key to continue."

				sudo dpkg --add-architecture i386

				if which wget; then
					wget -O /tmp/Release.key https://dl.winehq.org/wine-builds/Release.key
				else
					curl -o /tmp/Release.key https://dl.winehq.org/wine-builds/Release.key
				fi
				sudo apt-key add /tmp/Release.key
				rm /tmp/Release.key

				codename=$(lsb_release -cs)
				echo "deb https://dl.winehq.org/wine-builds/debian $codename main" | sudo tee -a /etc/apt/sources.list
			fi

			if dpkg -l apt-transport-https > /dev/null; then
				echo "apt-transport-https installed"
			else
				sudo apt-get -y install apt-transport-https
			fi
			sudo apt-get update
			;;

		*)
			echo "This version of Debian is not supported."
			exit 1
			;;
	esac
}

install_packages_arch() {
	packages=("screen" "unzip" "wine" "xorg-server-xvfb")

	for package in ${packages[@]}; do
		echo "checking for installation of $package..."
		if pacman -Qi $package > /dev/null; then
			echo "already installed $package !"
		else
			echo "need to install $package !"
			packagesinst+=("$package")
		fi
	done

	if [ ${#packagesinst[@]} -gt 0 ]; then
		echo -e "\nThe following packages and their dependencies will be installed: (press any key to continue)"
		echo -e "${packagesinst[@]}\n"
		qread ""
		yes | sudo pacman --noconfirm -S ${packagesinst[@]}
	else
		echo -e "\nRequired packages already installed."
	fi
}

install_packages_fedora() {
	packages=("screen" "unzip" "winehq-devel" "xorg-x11-server-Xvfb")

	for package in ${packages[@]}; do
		echo "checking for installation of $package..."
		if [ $(rpm -qa $package | wc -l) == 0 ]; then
			echo "need to install $package !"
			packagesinst+=("$package")
		fi
	done

	if [ ${#packagesinst[@]} -gt 0 ]; then
		echo -e "\nThe following packages and their dependencies will be installed: (press any key to continue)"
		echo -e "${packagesinst[@]}\n"
		qread ""
		sudo dnf --assumeyes install ${packagesinst[@]}
	else
		echo -e "\nRequired packages already installed."
	fi
}

install_packages_ubuntu() {
	case "$VERSION_ID" in
		14.04|14.10|15.04|15.10|16.04|16.10|17.04|17.10|18.04|7|8|9)
			packages=("screen" "unzip" "winehq-devel" "xvfb")

			for package in ${packages[@]}; do
				echo "checking for installation of $package..."
				if dpkg -l $package > /dev/null; then
					echo "already installed $package !"
				else
					echo "need to install $package !"
					packagesinst+=("$package")
				fi
			done

			if [ ${#packagesinst[@]} -gt 0 ]; then
				echo -e "\nThe following packages and their dependencies will be installed: (press any key to continue)"
				echo -e "${packagesinst[@]}\n"
				qread ""
				sudo apt-get -y install ${packagesinst[@]}
			else
				echo -e "\nRequired packages already installed.\n"
			fi
			;;

		*)
			echo "This version of Ubuntu or Debian is not supported."
			exit 1
			;;
	esac
}

install_packages_fbsd() {
	if [ $VERSION_ID != "11.2" ]; then
		echo "Only FreeBSD 11.2 is currently supported."
		exit 1
	fi

	packages=("screen" "unzip" "i386-wine-devel" "xorg-vfbserver" "xauth")

	for package in ${packages[@]}; do
		echo "checking for installation of $package..."	
		if pkg info $package > /dev/null; then
			echo "already installed $package !"
		else
			echo "need to install $package !"
			packagesinst+=("$package")			
		fi
	done

	if [ ${#packagesinst[@]} -gt 0 ]; then
		echo -e "\nThe following packages and their dependencies will be installed: (press any key to continue)"
		echo -e "${packagesinst[@]}\n"
		qread ""
		sudo pkg install -y ${packagesinst[@]}
	else
		echo -e "\nRequired packages already installed.\n"
	fi
}

install_deps() {
	motd

	# requires sudo for some functionality
	sudo_check

	# grab distribution information
	if [ $(uname) == "FreeBSD" ]; then
		NAME="FreeBSD"
		VERSION=$(uname -r)
		VERSION_ID=$(echo $VERSION | cut -d- -f1)
		ID="fbsd"
	else
		source /etc/os-release
	fi
	echo -e "Detected distro $NAME $VERSION (internally: $ID)\n"

	if [ ! -z "$INSTALL_AS_ID" ]; then
		ID=$INSTALL_AS_ID
		echo "forcing install as $ID"
	fi

	if [ ! -z "$INSTALL_AS_VERSION" ]; then
		VERSION=$INSTALL_AS_VERSION
		echo "with distro version $VERSION"
	fi

	# create the installation directory if it doesn't exist and enter it
	if [ -z "$1" ]; then
		INSTALL_DIR="$PWD/blockland"
	else
		INSTALL_DIR="$1"
	fi

	create_install_dir

	override_check

	cp "$0" "$INSTALL_DIR"
	cd "$INSTALL_DIR"
	chmod +x "$0"
	echo -e "using $INSTALL_DIR as the installation directory\n"

	# enable repositories
	case "$ID" in
		arch) enable_repo_arch ;;
		fedora) enable_repo_fedora ;;
		ubuntu) enable_repo_ubuntu ;;
		debian) enable_repo_debian ;;
		fbsd) ;;
		*)
			echo "Unknown distro $ID version $VERSION"
			exit 1
			;;
	esac

	# install required packages
	packagesinst=()
	case "$ID" in
		arch) install_packages_arch ;;
		fedora) install_packages_fedora ;;
		ubuntu|debian) install_packages_ubuntu ;;
		fbsd) install_packages_fbsd ;;
		*)
			echo "Unknown distro $ID version $VERSION"
			exit 1
			;;
	esac

	# download Blockland itself
	gather_and_unpack_blockland

	echo -e "\nInstallation complete! Navigate to $INSTALL_DIR and use './runblsrv.sh -g Freebuild' to run a Freebuild server!"
	exit 0
}

OPTIND=1
while getopts "d:qf:i:g:an:lzh" opt; do
	case "$opt" in
	f)	USE_FILE_FOR_BL_DATA=$(realpath "$OPTARG")
		;;
	i)	INSTALLING=true
		INSTALL_TO=$(realpath "$OPTARG")
		;;
	a)	ATTACH=true
		;;
	g)	GAMEMODE=$OPTARG
		;;
	n)	SERVER_NAME="$OPTARG"
		;;
	l)	DEDICATED_MODE="-dedicatedLAN"
		;;
	z)	NO_SCREEN=true
		ATTACH=false
		;;
	q)	BE_QUIET=true
		;;
	d)	INSTALL_AS_ID=$(echo "$OPTARG" | cut -d, -f1)
		INSTALL_AS_VERSION=$(echo "$OPTARG" | cut -d, -f2)
		;;
	h|?) echo "---===<| Blockland Dedicated Server Script |>===---"
		echo "version 1.3.1 -- October 12th, 2018 22:19 CDT"
		echo "TheBlackParrot (BL_ID 18701)"
		echo "https://github.com/TheBlackParrot/blockland-dedicated-server-launcher"
		echo ""
		echo "Usage: ./runblsrv.sh [options]"
		echo ""
		echo "Launcher Options:"
		echo "    -a             Automatically attach to the session"
		echo "    -g [gamemode]  Specify a gamemode"
		echo "    -n [name]      Set a custom name for the screen session"
		echo "    -l             Run a LAN server"
		echo "    -z             Don't attach to a screen session"
		echo "Installation Options:"
		echo "    -i [dir]       Install dependencies"
		echo "    -f [file]      Override downloading game data and use a local file instead"
		echo "    -q             Bypass all interactive prompts"
		echo "    -d [distro,v]  Force the installer to use a different Linux distro"
		exit 1
		;;
	esac
done

if $INSTALLING; then
	install_deps "$INSTALL_TO"
	exit 1
fi

shift $((OPTIND-1))
[ "$1" = "--" ] && shift


SERVER_PATH=$(dirname "$(readlink -f "$0")")
echo "Using $SERVER_PATH as the server directory."
PORT=$(cat "$SERVER_PATH/config/server/prefs.cs" | grep '$Pref::Server::Port' | sed 's/[^0-9]*//g')
echo "Should be running on port $PORT."
if [ -z "$SERVER_NAME" ]; then
	SERVER_NAME="BL$PORT"
fi


if [ ! -f "$SERVER_PATH/Blockland.exe" ]; then
	echo "Blockland executable is missing!"
	exit 1
fi

if [ ! -f "$SERVER_PATH/Add-Ons/Gamemode_$GAMEMODE/gamemode.txt" ]; then
	if [ ! -f "$SERVER_PATH/Add-Ons/GameMode_$GAMEMODE/gamemode.txt" ]; then
		if [ ! -f "$SERVER_PATH/Add-Ons/Gamemode_$GAMEMODE.zip" ]; then
			if [ ! -f "$SERVER_PATH/Add-Ons/GameMode_$GAMEMODE.zip" ]; then
				echo "Gamemode_$GAMEMODE does not exist in your Add-Ons folder!"
				exit 1
			fi
		fi
	fi
fi


if [ $(screen -list | grep -c "$SERVER_NAME") -gt 0 ]; then
	echo "Session already running on screen $SERVER_NAME, please shut that down first."
	exit 1
fi


if [ $(uname) == "FreeBSD" ]; then
	if $(ps aux | grep "Xvfb :9"); then
		echo "X server display 9 already running"
	else
		Xvfb :9 -screen 0 800x600x16 &
	fi

	export DISPLAY=:9

	if [ $NO_SCREEN = false ]; then
		screen -dmS \
			"$SERVER_NAME" \
				wine wineconsole \
					--backend=curses \
					"$SERVER_PATH/Blockland.exe" \
					ptlaaxobimwroe \
					$DEDICATED_MODE \
					-gamemode "$GAMEMODE"
	else
		wine wineconsole \
			--backend=curses \
			"$SERVER_PATH/Blockland.exe" \
			ptlaaxobimwroe \
			$DEDICATED_MODE \
			-gamemode "$GAMEMODE"
	fi
else
	if [ $NO_SCREEN = false ]; then
		screen -dmS \
			"$SERVER_NAME" \
			xvfb-run -a \
				-n 103 \
				-e /dev/stdout \
				wine wineconsole \
					--backend=curses \
					"$SERVER_PATH/Blockland.exe" \
					ptlaaxobimwroe \
					$DEDICATED_MODE \
					-gamemode "$GAMEMODE"
	else
		xvfb-run -a \
			-n 100 \
			-e /dev/stdout \
			wine wineconsole \
				--backend=curses \
				"$SERVER_PATH/Blockland.exe" \
				ptlaaxobimwroe \
				$DEDICATED_MODE \
				-gamemode "$GAMEMODE"
	fi
fi

if [ $NO_SCREEN = false ]; then
	sleep 3

	if [ $(screen -list | grep -c "$SERVER_NAME") -gt 0 ]; then
		echo "Session started on screen $SERVER_NAME"
		if [ "$ATTACH" = true ]; then
			screen -x "$SERVER_NAME"
		else
			screen -list
		fi
	else
		echo "Failed to start server."
		exit 1
	fi
fi