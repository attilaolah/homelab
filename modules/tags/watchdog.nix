# Keep the hardware watchdog active during normal runtime.
# Reboot watchdog timeout stays at systemd's default (10min).
{systemd.settings.Manager.RuntimeWatchdogSec = "2min";}
