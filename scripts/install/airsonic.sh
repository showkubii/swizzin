#!/bin/bash

#shellcheck source=sources/functions/utils
. /etc/swizzin/sources/functions/utils
master=$(_get_master_username)
distribution=$(lsb_release -is)

airsonicdir="/opt/airsonic" #Where to install airosnic
airsonicusr="airsonic"      #Who to run airsonic as

#shellcheck source=sources/functions/java
. /etc/swizzin/sources/functions/java
install_java8

airsonic_dl() {
	echo_progress_start "Downloading Airsonic binary"
	mkdir $airsonicdir -p
	# TODO make dynamic
	dlurl=$(curl -s https://api.github.com/repos/airsonic/airsonic/releases/latest | grep "browser_download_url" | grep "airsonic.war" | head -1 | cut -d\" -f 4)
	echo_log_only "dlurl = $dlurl"
	if ! wget "$dlurl" -O ${airsonicdir}/airsonic.war >> "$log" 2>&1; then
		echo_error "Download failed!"
		exit 1
	fi
	useradd $airsonicusr --system -d "$airsonicdir" >> "$log" 2>&1
	usermod -a -G "$master" $airsonicusr
	chown -R $airsonicusr:$airsonicusr $airsonicdir
	echo_progress_done "Binary DL'd"
}

airsonic_systemd() {
	echo_progress_start "Setting up systemd service"
	wget https://raw.githubusercontent.com/airsonic/airsonic/master/contrib/airsonic.service -O /etc/systemd/system/airsonic.service >> "$log" 2>&1
	sed -i "s|/var/airsonic|$airsonicdir|g" /etc/systemd/system/airsonic.service
	sed -i 's|PORT=8080|PORT=8185|g' /etc/systemd/system/airsonic.service

	defconfdir="/etc/sysconfig"
	if [[ $distribution == "Debian" ]]; then
		defconfdir="/etc/defaults"
	fi
	wget https://raw.githubusercontent.com/airsonic/airsonic/master/contrib/airsonic-systemd-env -O "${defconfdir}"/airsonic >> "$log" 2>&1

	systemctl daemon-reload -q
	echo_progress_done "Service installed"
}

airsonic_nginx() {
	if [[ -f /install/.nginx.lock ]]; then
		echo_progress_start "Configuring nginx"
		bash /usr/local/bin/swizzin/nginx/airsonic.sh
		systemctl reload nginx
		echo_progress_done
	else
		echo_info "Airosnic will run on <IP/domain.tld>${bold}:8185"
	fi
}

airsonic_start() {
	echo_progress_start "Enabling and starting Airsonic"
	systemctl -q enable airsonic --now
	echo_progress_done
}

airsonic_dl
airsonic_systemd
airsonic_nginx
airsonic_start

echo_success "Airsonic installed"
echo_warn "Wait for Airsonic to start up (max 5 mins) and continue the set up in the browser.\nYou can use \`journalctl -fu airsonic\` to follow the progress."

if [[ -f /install/.subsonic.lock ]]; then
	echo_info "If you would like to migrate from Subsonic, please see see the following article"
	echo_docs "applications/airsonic#migrating-from-subsonic"
fi

mark_installed airsonic