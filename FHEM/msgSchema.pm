# $Id$
##############################################################################
#
#     msgSchema.pm
#     Schema database for FHEM modules and their messaging options.
#     These commands are being used as default setting for FHEM command 'msg'
#     unless there is an explicit msgCmd* attribute.
#
#     FHEM module authors may request to extend this file
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

sub msgSchema_Initialize() {
}

package msgSchema;

use strict;
use warnings;

# FHEM module schema definitions for messaging commands
my $db = {
    'audio' => {

        'AMAD' => {
            'Normal'        => 'set %DEVICE% ttsMsg %MSG%',
            'ShortPrio'     => 'set %DEVICE% ttsMsg %MSGSHRT%',
            'Short'         => 'set %DEVICE% ttsMsg %MSGSHRT%',
            'defaultValues' => {
                'ShortPrio' => {
                    'MSGSH' => 'Achtung!',
                },
                'Short' => {
                    'MSGSH' => 'Hinweis!',
                },
            },
        },

        'SB_PLAYER' => {
            'Normal'        => 'set %DEVICE% talk |%TITLE%| %MSG%',
            'ShortPrio'     => 'set %DEVICE% talk |%TITLE%| %MSGSHRT%',
            'Short'         => 'set %DEVICE% talk |%TITLE%| %MSGSHRT%',
            'defaultValues' => {
                'Normal' => {
                    'TITLE' => 'Announcement',
                },
                'ShortPrio' => {
                    'MSGSH' => 'Achtung!',
                    'TITLE' => 'Announcement',
                },
                'Short' => {
                    'MSGSH' => '',
                    'TITLE' => 'Announcement',
                },
            },
        },

        'SONOSPLAYER' => {
            'Normal' =>
              'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %MSGSHRT%',
            'ShortPrio' =>
              'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %SHOUTOUT%',
            'Short' =>
              'set %DEVICE% Speak %VOLUME% %LANG% |%TITLE%| %SHOUTOUT%',
            'defaultValues' => {
                'Normal' => {
                    'VOLUME' => 38,
                    'LANG'   => 'de',
                    'TITLE'  => 'Announcement',
                },
                'ShortPrio' => {
                    'VOLUME'   => 33,
                    'LANG'     => 'de',
                    'TITLE'    => 'Announcement',
                    'SHOUTOUT' => 'Achtung!',
                },
                'Short' => {
                    'VOLUME'   => 28,
                    'LANG'     => 'de',
                    'TITLE'    => 'Announcement',
                    'SHOUTOUT' => '',
                },
            },
        },

        'Text2Speech' => {
            'Normal'        => 'set %DEVICE% tts %MSG%',
            'ShortPrio'     => 'set %DEVICE% tts %MSGSHRT%',
            'Short'         => 'set %DEVICE% tts %MSGSHRT%',
            'defaultValues' => {
                'ShortPrio' => {
                    'MSGSH' => 'Achtung!',
                },
                'Short' => {
                    'MSGSH' => 'Hinweis!',
                },
            },
        },

    },

    'light' => {

        'HUEDevice' => {
            'Normal' =>
'{ my $d=\'%DEVICE%\'; my $state=ReadingsVal($d,"state","off"); fhem "set $d blink 2 1"; fhem "sleep 4.25; set $d:FILTER=state!=$state $state"; }',
            'High' =>
'{ my $d=\'%DEVICE%\'; my $state=ReadingsVal($d,"state","off"); fhem "set $d blink 10 1"; fhem "sleep 20.25; set $d:FILTER=state!=$state $state"; }',
            'Low' => 'set %DEVICE% alert select',
        },

    },

    'mail' => {

        'fhemMsgMail' => {
            'Normal' =>
'{ my $d=\'%DEVICE%\'; my $title=\'%TITLE%\'; my $msg=\'%MSG%\'; system("echo \'$msg\' | /usr/bin/mail -s \'$title\' \'$d\'"); }',
            'High' =>
'{ my $d=\'%DEVICE%\'; my $title=\'%TITLE%\'; my $msg=\'%MSG%\'; system("echo \'$msg\' | /usr/bin/mail -s \'$title\' \'$d\'"); }',
            'Low' =>
'{ my $d=\'%DEVICE%\'; my $title=\'%TITLE%\'; my $msg=\'%MSG%\'; system("echo \'$msg\' | /usr/bin/mail -s \'$title\' \'$d\'"); }',
            'defaultValues' => {
                'Normal' => {
                    'TITLE' => 'System Message',
                },
                'High' => {
                    'TITLE' => 'System Message',
                },
                'Low' => {
                    'TITLE' => 'System Message',
                },
            },

        },
    },

    'push' => {

        'Fhemapppush' => {
            'Normal'        => 'set %DEVICE% message \'%MSG%\' %ACTION%',
            'High'          => 'set %DEVICE% message \'%MSG%\' %ACTION%',
            'Low'           => 'set %DEVICE% message \'%MSG%\' %ACTION%',
            'defaultValues' => {
                'Normal' => {
                    'ACTION' => '',
                },
                'High' => {
                    'ACTION' => '',
                },
                'Low' => {
                    'ACTION' => '',
                },
            },
        },

        'Jabber' => {
            'Normal' => 'set %DEVICE% msg%JabberMsgType% %RECIPIENT% %MSG%',
            'High'   => 'set %DEVICE% msg%JabberMsgType% %RECIPIENT% %MSG%',
            'Low'    => 'set %DEVICE% msg%JabberMsgType% %RECIPIENT% %MSG%',
            'defaultValues' => {
                'Normal' => {
                    'JabberMsgType' => '',
                },
                'High' => {
                    'JabberMsgType' => '',
                },
                'Low' => {
                    'JabberMsgType' => '',
                },
            },
        },

        'Pushbullet' => {
            'Normal' => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
            'High'   => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
            'Low'    => 'set %DEVICE% message %MSG% | %TITLE% %RECIPIENT%',
            'defaultValues' => {
                'Normal' => {
                    'RECIPIENT' => '',
                },
                'High' => {
                    'RECIPIENT' => '',
                },
                'Low' => {
                    'RECIPIENT' => '',
                },
            },
        },

        'PushNotifier' => {
            'Normal' => 'set %DEVICE% message %MSG%',
            'High'   => 'set %DEVICE% message %MSG%',
            'Low'    => 'set %DEVICE% message %MSG%',
        },

        'Pushover' => {
            'Normal' =>
'set %DEVICE% %Pushover_PTYPE% title=\'%TITLE%\' device=\'%RECIPIENT%:%TERMINAL%\' priority=%PRIORITY% sound=\'%Pushover_SOUND%\' retry=%RETRY% expire=%EXPIRE% url_title=%URLTITLE% action=%ACTION% cancel_id=%Pushover_CANCELID% message=\'%MSG%\'',
            'High' =>
'set %DEVICE% %Pushover_PTYPE% title=\'%TITLE%\' device=\'%RECIPIENT%:%TERMINAL%\' priority=%PRIORITY% sound=\'%Pushover_SOUND%\' retry=%RETRY% expire=%EXPIRE% url_title=%URLTITLE% action=%ACTION% cancel_id=%Pushover_CANCELID% message=\'%MSG%\'',
            'Low' =>
'set %DEVICE% %Pushover_PTYPE% title=\'%TITLE%\' device=\'%RECIPIENT%:%TERMINAL%\' priority=%PRIORITY% sound=\'%Pushover_SOUND%\' retry=%RETRY% expire=%EXPIRE% url_title=%URLTITLE% action=%ACTION% cancel_id=%Pushover_CANCELID% message=\'%MSG%\'',
            'defaultValues' => {
                'Normal' => {
                    'RECIPIENT'         => '',
                    'TERMINAL'          => '',
                    'RETRY'             => '',
                    'EXPIRE'            => '',
                    'URLTITLE'          => '',
                    'ACTION'            => '',
                    'Pushover_PTYPE'    => 'msg',
                    'Pushover_SOUND'    => '',
                    'Pushover_CANCELID' => '',
                },
                'High' => {
                    'RECIPIENT'         => '',
                    'TERMINAL'          => '',
                    'RETRY'             => '120',
                    'EXPIRE'            => '600',
                    'URLTITLE'          => '',
                    'ACTION'            => '',
                    'Pushover_PTYPE'    => 'msg',
                    'Pushover_SOUND'    => '',
                    'Pushover_CANCELID' => '',
                },
                'Low' => {
                    'RECIPIENT'         => '',
                    'TERMINAL'          => '',
                    'RETRY'             => '',
                    'EXPIRE'            => '',
                    'URLTITLE'          => '',
                    'ACTION'            => '',
                    'Pushover_PTYPE'    => 'msg',
                    'Pushover_SOUND'    => '',
                    'Pushover_CANCELID' => '',
                },
            },
        },

        'Pushsafer' => {
            'Normal' =>
'set %DEVICE% message "%MSG%" title="%TITLE%" key="%RECIPIENT%" device="%TERMINAL%" sound="%Pushsafer_SOUND%" icon="%Pushsafer_ICON%" vibration="%Pushsafer_VIBRATION%" url="%ACTION%" urlText="%URLTITLE%" ttl="%EXPIRE%"',
            'High' =>
'set %DEVICE% message "%MSG%" title="%TITLE%" key="%RECIPIENT%" device="%TERMINAL%" sound="%Pushsafer_SOUND%" icon="%Pushsafer_ICON%" vibration="%Pushsafer_VIBRATION%" url="%ACTION%" urlText="%URLTITLE%" ttl="%EXPIRE%"',
            'Low' =>
'set %DEVICE% message "%MSG%" title="%TITLE%" key="%RECIPIENT%" device="%TERMINAL%" sound="%Pushsafer_SOUND%" icon="%Pushsafer_ICON%" vibration="%Pushsafer_VIBRATION%" url="%ACTION%" urlText="%URLTITLE%" ttl="%EXPIRE%"',
            'defaultValues' => {
                'Normal' => {
                    'RECIPIENT'           => '',
                    'TERMINAL'            => '',
                    'EXPIRE'              => '',
                    'URLTITLE'            => '',
                    'ACTION'              => '',
                    'Pushsafer_ICON'      => '',
                    'Pushsafer_SOUND'     => '',
                    'Pushsafer_VIBRATION' => '1',
                },
                'High' => {
                    'RECIPIENT'           => '',
                    'TERMINAL'            => '',
                    'EXPIRE'              => '',
                    'URLTITLE'            => '',
                    'ACTION'              => '',
                    'Pushsafer_ICON'      => '',
                    'Pushsafer_SOUND'     => '',
                    'Pushsafer_VIBRATION' => '2',
                },
                'Low' => {
                    'RECIPIENT'           => '',
                    'TERMINAL'            => '',
                    'EXPIRE'              => '',
                    'URLTITLE'            => '',
                    'ACTION'              => '',
                    'Pushsafer_ICON'      => '',
                    'Pushsafer_SOUND'     => '',
                    'Pushsafer_VIBRATION' => '',
                },
            },
        },

        'TelegramBot' => {
            'Normal'        => 'set %DEVICE% message %RECIPIENT% %MSG%',
            'High'          => 'set %DEVICE% message %RECIPIENT% %MSG%',
            'Low'           => 'set %DEVICE% message %RECIPIENT% %MSG%',
            'defaultValues' => {
                'Normal' => {
                    'RECIPIENT' => '',
                },
                'High' => {
                    'RECIPIENT' => '',
                },
                'Low' => {
                    'RECIPIENT' => '',
                },
            },
        },

        'yowsup' => {
            'Normal' => 'set %DEVICE% send %RECIPIENT% %MSG%',
            'High'   => 'set %DEVICE% send %RECIPIENT% %MSG%',
            'Low'    => 'set %DEVICE% send %RECIPIENT% %MSG%',
        },

    },

    'screen' => {

        'AMAD' => {
            'Normal' => 'set %DEVICE% screenMsg %MSG%',
            'High'   => 'set %DEVICE% screenMsg %MSG%',
            'Low'    => 'set %DEVICE% screenMsg %MSG%',
        },

        'ENIGMA2' => {
            'Normal' => 'set %DEVICE% msg %ENIGMA2_TYPE% %TIMEOUT% %MSG%',
            'High'   => 'set %DEVICE% msg %ENIGMA2_TYPE% %TIMEOUT% %MSG%',
            'Low'    => 'set %DEVICE% msg %ENIGMA2_TYPE% %TIMEOUT% %MSG%',
            'defaultValues' => {
                'Normal' => {
                    'ENIGMA2_TYPE' => 'info',
                    'TIMEOUT'      => 8,
                },
                'High' => {
                    'ENIGMA2_TYPE' => 'attention',
                    'TIMEOUT'      => 12,
                },
                'Low' => {
                    'ENIGMA2_TYPE' => 'message',
                    'TIMEOUT'      => 8,
                },
            },
        },

        'KODI' => {
            'Normal' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %KODI_ICON%"; }',
            'High' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %KODI_ICON%"; }',
            'Low' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %KODI_ICON%"; }',
            'defaultValues' => {
                'Normal' => {
                    'TIMEOUT'   => 8,
                    'TITLE'     => 'Info',
                    'KODI_ICON' => 'info',
                },
                'High' => {
                    'TIMEOUT'   => 12,
                    'TITLE'     => 'Warning',
                    'KODI_ICON' => 'warning',
                },
                'Low' => {
                    'TIMEOUT'   => 8,
                    'TITLE'     => 'Notice',
                    'KODI_ICON' => '',
                },
            },
        },

        'PostMe' => {
            'Normal' =>
'set %DEVICE% create %TITLESHRT2%_%MSGID%; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSGDATETIME%; set %DEVICE% add %TITLESHRT2%_%MSGID% %TITLE%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_TO%%SRCALIAS% (%SOURCE%); set %DEVICE% add %TITLESHRT2%_%MSGID% _________________________; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSG%',
            'High' =>
'set %DEVICE% create %TITLESHRT2%_%MSGID%; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSGDATETIME%; set %DEVICE% add %TITLESHRT2%_%MSGID% %TITLE%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_PRIO%%PRIOCAT%/%PRIORITY%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_TO%%SRCALIAS% (%SOURCE%); set %DEVICE% add %TITLESHRT2%_%MSGID% _________________________; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSG%',
            'Low' =>
'set %DEVICE% create %TITLESHRT2%_%MSGID%; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSGDATETIME%; set %DEVICE% add %TITLESHRT2%_%MSGID% %TITLE%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_PRIO%%PRIOCAT%/%PRIORITY%; set %DEVICE% add %TITLESHRT2%_%MSGID% %PostMe_TO%%SRCALIAS% (%SOURCE%); set %DEVICE% add %TITLESHRT2%_%MSGID% _________________________; set %DEVICE% add %TITLESHRT2%_%MSGID% %MSG%',
            'defaultValues' => {
                'Normal' => {
                    'TITLE'       => 'Info',
                    'PostMe_TO'   => 'To: ',
                    'PostMe_SUB'  => 'Subject: ',
                    'PostMe_PRIO' => 'Priority: ',
                },
                'High' => {
                    'TITLE'       => 'Warning',
                    'PostMe_TO'   => 'To',
                    'PostMe_SUB'  => 'Subject',
                    'PostMe_PRIO' => 'Priority',
                },
                'Low' => {
                    'TITLE'       => 'Notice',
                    'PostMe_TO'   => 'To: ',
                    'PostMe_SUB'  => 'Subject: ',
                    'PostMe_PRIO' => 'Priority: ',
                },
            },
        },

        'XBMC' => {
            'Normal' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %XBMC_ICON%"; }',
            'High' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %XBMC_ICON%"; }',
            'Low' =>
'{ my $d=\'%DEVICE%\'; my $msg=\'%MSG%\'; my $title=\'%TITLE%\'; my $timeout=%TIMEOUT%*1000; fhem "set $d msg \'$title\' \'$msg\' $timeout %XBMC_ICON%"; }',
            'defaultValues' => {
                'Normal' => {
                    'TIMEOUT'   => 8,
                    'TITLE'     => 'Info',
                    'XBMC_ICON' => 'info',
                },
                'High' => {
                    'TIMEOUT'   => 12,
                    'TITLE'     => 'Warning',
                    'XBMC_ICON' => 'warning',
                },
                'Low' => {
                    'TIMEOUT'   => 8,
                    'TITLE'     => 'Notice',
                    'XBMC_ICON' => '',
                },
            },
        },

    },
};

sub get {
    return $db;
}

1;
