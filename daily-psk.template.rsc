#!rsc by RouterOS
# RouterOS script: daily-psk%TEMPL%
# Copyright (c) 2013-2025 Christian Hesse <mail@eworm.de>
#                         Michael Gisbers <michael@gisbers.de>
# https://rsc.eworm.de/COPYING.md
#
# requires RouterOS, version=7.15
#
# update daily PSK (pre shared key)
# https://rsc.eworm.de/doc/daily-psk.md
#
# !! This is just a template to generate the real script!
# !! Pattern '%TEMPL%' is replaced, paths are filtered.

:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:local ExitOK false;
:do {
  :local ScriptName [ :jobname ];

  :global DailyPskMatchComment;
  :global DailyPskQrCodeUrl;
  :global Identity;

  :global FormatLine;
  :global LogPrint;
  :global ScriptLock;
  :global SendNotification2;
  :global SymbolForNotification;
  :global UrlEncode;
  :global WaitForFile;
  :global WaitFullyConnected;

  :if ([ $ScriptLock $ScriptName ] = false) do={
    :set ExitOK true;
    :error false;
  }
  $WaitFullyConnected;

  # return pseudo-random string for PSK
  :local GeneratePSK do={
    :local Date [ :tostr $1 ];

    :global DailyPskSecrets;

    :global ParseDate;

    :set Date [ $ParseDate $Date ];

    :local A ((14 - ($Date->"month")) / 12);
    :local B (($Date->"year") - $A);
    :local C (($Date->"month") + 12 * $A - 2);
    :local WeekDay (7000 + ($Date->"day") + $B + ($B / 4) - ($B / 100) + ($B / 400) + ((31 * $C) / 12));
    :set WeekDay ($WeekDay - (($WeekDay / 7) * 7));

    :return (($DailyPskSecrets->0->(($Date->"day") - 1)) . \
      ($DailyPskSecrets->1->(($Date->"month") - 1)) . \
      ($DailyPskSecrets->2->$WeekDay));
  }

  :local Seen ({});
  :local Date [ /system/clock/get date ];
  :local NewPsk [ $GeneratePSK $Date ];

  :foreach AccList in=[ /caps-man/access-list/find where comment~$DailyPskMatchComment ] do={
  :foreach AccList in=[ /interface/wifi/access-list/find where comment~$DailyPskMatchComment ] do={
  :foreach AccList in=[ /interface/wireless/access-list/find where comment~$DailyPskMatchComment ] do={
    :local SsidRegExp [ /caps-man/access-list/get $AccList ssid-regexp ];
    :local SsidRegExp [ /interface/wifi/access-list/get $AccList ssid-regexp ];
    :local Configuration ([ /caps-man/configuration/find where ssid~$SsidRegExp ]->0);
    :local Configuration ([ /interface/wifi/configuration/find where ssid~$SsidRegExp ]->0);
    :local Ssid [ /caps-man/configuration/get $Configuration ssid ];
    :local Ssid [ /interface/wifi/configuration/get $Configuration ssid ];
    :local OldPsk [ /caps-man/access-list/get $AccList private-passphrase ];
    :local OldPsk [ /interface/wifi/access-list/get $AccList passphrase ];
    # /caps-man/ /interface/wifi/ above - /interface/wireless/ below
    :local IntName [ /interface/wireless/access-list/get $AccList interface ];
    :local Ssid [ /interface/wireless/get $IntName ssid ];
    :local OldPsk [ /interface/wireless/access-list/get $AccList private-pre-shared-key ];
    :local Skip 0;

    :if ($NewPsk != $OldPsk) do={
      $LogPrint info $ScriptName ("Updating daily PSK for '" . $Ssid . "' to '" . $NewPsk . "' (was '" . $OldPsk . "')");
      /caps-man/access-list/set $AccList private-passphrase=$NewPsk;
      /interface/wifi/access-list/set $AccList passphrase=$NewPsk;
      /interface/wireless/access-list/set $AccList private-pre-shared-key=$NewPsk;

      :if ([ :len [ /caps-man/actual-interface-configuration/find where configuration.ssid=$Ssid !disabled ] ] > 0) do={
      :if ([ :len [ /interface/wifi/find where configuration.ssid=$Ssid !disabled ] ] > 0) do={
      :if ([ :len [ /interface/wireless/find where name=$IntName !disabled ] ] = 1) do={
        :if ($Seen->$Ssid = 1) do={
          $LogPrint debug $ScriptName ("Already sent a mail for SSID " . $Ssid . ", skipping.");
        } else={
          :local Link ($DailyPskQrCodeUrl . \
              "?scale=8&level=1&ssid=" . [ $UrlEncode $Ssid ] . "&pass=" . [ $UrlEncode $NewPsk ]);
          $SendNotification2 ({ origin=$ScriptName; \
            subject=([ $SymbolForNotification "calendar" ] . "daily PSK " . $Ssid); \
            message=("This is the daily PSK on " . $Identity . ":\n\n" . \
              [ $FormatLine "SSID" $Ssid 8 ] . "\n" . \
              [ $FormatLine "PSK" $NewPsk 8 ] . "\n" . \
              [ $FormatLine "Date" $Date 8 ] . "\n\n" . \
              "A client device specific rule must not exist!"); link=$Link });
          :set ($Seen->$Ssid) 1;
        }
      }
    }
  }
} on-error={
  :global ExitError; $ExitError $ExitOK [ :jobname ];
}
