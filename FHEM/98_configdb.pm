# $Id$
#

package main;
use strict;
use warnings;
use feature qw/say switch/;
use configDB;

sub CommandConfigdb($$);

my @pathname;

sub configdb_Initialize($$) {
  my %hash = (  Fn => "CommandConfigdb",
               Hlp => "help     ,access additional functions from configDB" );
  $cmds{configdb} = \%hash;
}

sub CommandConfigdb($$) {
	my ($cl, $param) = @_;

#	my @a = split(/ /,$param);
	my @a = split("[ \t][ \t]*", $param);
	my ($cmd, $param1, $param2) = @a;
	$cmd    = $cmd    ? $cmd    : "";
	$param1 = $param1 ? $param1 : "";
	$param2 = $param2 ? $param2 : "";

	my $configfile = $attr{global}{configfile};
	return "\n error: configDB not used!" unless($configfile eq 'configDB' || $cmd eq 'migrate');

	my $ret;

	given ($cmd) {

		when ('attr') {
			Log3('configdb', 4, 'configdb: attr $param1 $param2 requested.');
			if ($param1 eq "" && $param2 eq "") {
			# list attributes
				foreach my $c (sort keys %{$attr{configdb}}) {
					my $val = $attr{configdb}{$c};
					$val =~ s/;/;;/g;
					$val =~ s/\n/\\\n/g;
					$ret .= "attr configdb $c $val\n";
				}
			} elsif($param2 eq "") {
			# delete attribute
				undef($attr{configdb}{$param1});
				$ret = " attribute $param1 deleted";
			} else {
			# set attribute
				$attr{configdb}{$param1} = $param2;
				$ret = " attribute $param1 set to value $param2";
			}
		}

		when ('diff') {
			return "\n Syntax: configdb diff <device> <version>" if @a != 3;
			Log3('configdb', 4, "configdb: diff requested for device: $param1 in version $param2.");
			$ret = _cfgDB_Diff($param1, $param2);
		}

		when ('filedelete') {
			return "\n Syntax: configdb fileexport <pathToFile>" if @a != 2;
			my $filename;
			if($param1 =~ m,^[./],) {
				$filename = $param1;
			} else {
				$filename  = $attr{global}{modpath};
				$filename .= "/$param1";
			}
			$ret = _cfgDB_Filedelete $filename;
		}

		when ('fileexport') {
			return "\n Syntax: configdb fileexport <pathToFile>" if @a != 2;
			my $filename;
			if($param1 =~ m,^[./],) {
				$filename = $param1;
			} else {
				$filename  = $attr{global}{modpath};
				$filename .= "/$param1";
			}
			$ret = _cfgDB_Fileexport $filename;
		}

		when ('fileimport') {
			return "\n Syntax: configdb fileimport <pathToFile>" if @a != 2;
			my $filename;
			if($param1 =~ m,^[./],) {
				$filename = $param1;
			} else {
				$filename  = $attr{global}{modpath};
				$filename .= "/$param1";
			}
			if ( -r $filename ) {
				my $filesize = -s $filename;
				$ret = _cfgDB_binFileimport($filename,$filesize);
			} elsif ( -e $filename) {
				$ret = "\n Read error on file $filename";
			} else {
				$ret = "\n File $filename not found.";
			}
		}

		when ('filelist') {
			return _cfgDB_Filelist;
		}

		when ('filemove') {
			return "\n Syntax: configdb filemove <pathToFile>" if @a != 2;
			my $filename;
			if($param1 =~ m,^[./],) {
				$filename = $param1;
			} else {
				$filename  = $attr{global}{modpath};
				$filename .= "/$param1";
			}
			if ( -r $filename ) {
				my $filesize = -s $filename;
				$ret  = _cfgDB_binFileimport ($filename,$filesize,1);
				$ret .= "\nFile $filename deleted from local filesystem.";
			} elsif ( -e $filename) {
				$ret = "\n Read error on file $filename";
			} else {
				$ret = "\n File $filename not found.";
			}
		}

		when ('fileshow') {
			my @rets = cfgDB_FileRead($param1);
			my $r = (int(@rets)) ? join "\n",@rets : "File $param1 not found in database.";
			return $r;
		}

		when ('info') {
			Log3('configdb', 4, "info requested.");
			$ret = _cfgDB_Info;
		}

		when ('list') {
			$param1 = $param1 ? $param1 : '%';
			$param2 = $param2 ? $param2 : 0;
			Log3('configdb', 4, "configdb: list requested for device: $param1 in version $param2.");
			$ret = _cfgDB_Search($param1,$param2,1);
		}

		when ('migrate') {
			return "\n Migration not possible. Already running with configDB!" if $configfile eq 'configDB';
			Log3('configdb', 4, "configdb: migration requested.");
			$ret = _cfgDB_Migrate;
		}

		when ('recover') {
			return "\n Syntax: configdb recover <version>" if @a != 2;
			Log3('configdb', 4, "configdb: recover for version $param1 requested.");
			$ret = _cfgDB_Recover($param1);
		}

		when ('reorg') {
			$param1 = $param1 ? $param1 : 3;
			Log3('configdb', 4, "configdb: reorg requested with keep: $param1.");
			$ret = _cfgDB_Reorg($a[1]);
		}

		when ('search') {
			return "\n Syntax: configdb search <searchTerm> [searchVersion]" if @a < 2;
			$param1 = $param1 ? $param1 : '%';
			$param2 = $param2 ? $param2 : 0;
			Log3('configdb', 4, "configdb: list requested for device: $param1 in version $param2.");
			$ret = _cfgDB_Search($param1,$param2);
		}

		when ('uuid') {
			$param1 = _cfgDB_Uuid;
			Log3('configdb', 4, "configdb: uuid requested: $param1");
			$ret = $param1;
		}

		default { 	
			$ret =	"\n Syntax:\n".
					"         configdb attr [attribute] [value]\n".
					"         configdb diff <device> <version>\n".
					"         configDB filedelete <pathToFilename>\n".
					"         configDB fileimport <pathToFilename>\n".
					"         configDB fileexport <pathToFilename>\n".
					"         configDB filelist\n".
					"         configDB filemove <pathToFilename>\n".
					"         configDB fileshow <pathToFilename>\n".
					"         configdb info\n".
					"         configdb list [device] [version]\n".
					"         configdb migrate\n".
					"         configdb recover <version>\n".
					"         configdb reorg [keepVersions]\n".
					"         configdb search <searchTerm> [version]\n".
					"         configdb uuid\n".
					"";
		}

	}

	return $ret;
	
}

1;

=pod
=begin html

<a name="configdb"></a>
<h3>configdb</h3>
	<ul>
		Starting with version 5079, fhem can be used with a configuration database instead of a plain text file (e.g. fhem.cfg).<br/>
		This offers the possibility to completely waive all cfg-files, "include"-problems and so on.<br/>
		Furthermore, configDB offers a versioning of several configuration together with the possibility to restore a former configuration.<br/>
		Access to database is provided via perl's database interface DBI.<br/>
		<br/>

		<b>Interaction with other modules</b><br/>
		<ul><br/>
			Currently the fhem modules<br/>
			<br/>
			<li>02_RSS.pm</li>
			<li>91_eventTypes</li>
			<li>93_DbLog.pm</li>
			<li>95_holiday.pm</li>
			<li>98_SVG.pm</li>
			<br/>
			will use configDB to read their configuration data from database<br/> 
			instead of formerly used configuration files inside the filesystem.<br/>
			<br/>
			This requires you to import your configuration files from filesystem into database.<br/>
			<br/>
			Example:<br/>
			<code>configdb fileimport FHEM/nrw.holiday</code><br/>
			<code>configdb fileimport FHEM/myrss.layout</code><br/>
			<code>configdb fileimport www/gplot/xyz.gplot</code><br/>
			<br/>
			<b>This does not affect the definitons of your holiday or RSS entities.</b><br/>
			<br/>
			<b>During migration all external configfiles used in current configuration<br/>
			will be imported aufmatically.</b><br>
			<br/>
			Each fileimport into database will overwrite the file if it already exists in database.<br/>
			<br/>
		</ul><br/>
<br/>

		<b>Prerequisits / Installation</b><br/>
		<ul><br/>
		<li>Please install perl package Text::Diff if not already installed on your system.</li><br/>
		<li>You must have access to a SQL database. Supported database types are SQLITE, MYSQL and POSTGRESQL.</li><br/>
		<li>The corresponding DBD module must be available in your perl environment,<br/>
				e.g. sqlite3 running on a Debian systems requires package libdbd-sqlite3-perl</li><br/>
		<li>Create an empty database, e.g. with sqlite3:<br/>
			<pre>
	mba:fhem udo$ sqlite3 configDB.db

	SQLite version 3.7.13 2012-07-17 17:46:21
	Enter ".help" for instructions
	Enter SQL statements terminated with a ";"
	sqlite> pragma auto_vacuum=2;
	sqlite> .quit

	mba:fhem udo$ 
			</pre></li>
		<li>The database tables will be created automatically.</li><br/>
		<li>Create a configuration file containing the connection string to access database.<br/>
			<br/>
			<b>IMPORTANT:</b>
			<ul><br/>
				<li>This file <b>must</b> be named "configDB.conf"</li>
				<li>This file <b>must</b> be located in the same directory containing fhem.pl and configDB.pm, e.g. /opt/fhem</li>
			</ul>
			<br/>
			<pre>
## for MySQL
################################################################
#%dbconfig= (
#	connection => "mysql:database=configDB;host=db;port=3306",
#	user => "fhemuser",
#	password => "fhempassword",
#);
################################################################
#
## for PostgreSQL
################################################################
#%dbconfig= (
#        connection => "Pg:database=configDB;host=localhost",
#        user => "fhemuser",
#        password => "fhempassword"
#);
################################################################
#
## for SQLite (username and password stay empty for SQLite)
################################################################
#%dbconfig= (
#        connection => "SQLite:dbname=/opt/fhem/configDB.db",
#        user => "",
#        password => ""
#);
################################################################
			</pre></li><br/>
		</ul>

		<b>Start with a complete new "fresh" fhem Installation</b><br/>
		<ul><br/>
			It's easy... simply start fhem by issuing following command:<br/><br/>
			<ul><code>perl fhem.pl configDB</code></ul><br/>

			<b>configDB</b> is a keyword which is recognized by fhem to use database for configuration.<br/>
			<br/>
			<b>That's all.</b> Everything (save, rereadcfg etc) should work as usual.
		</ul>

		<br/>
		<b>or:</b><br/>
		<br/>

		<b>Migrate your existing fhem configuration into the database</b><br/>
		<ul><br/>
			It's easy, too... <br/>
			<br/>
			<li>start your fhem the last time with fhem.cfg<br/><br/>
				<ul><code>perl fhem.pl fhem.cfg</code></ul></li><br/>
			<br/>
			<li>transfer your existing configuration into the database<br/><br/>
				<ul>enter<br/><br/><code>configdb migrate</code><br/>
				<br/>
				into frontend's command line</ul><br/></br>
				Be patient! Migration can take some time, especially on mini-systems like RaspberryPi or Beaglebone.<br/>
				Completed migration will be indicated by showing database statistics.<br/>
				Your original configfile will not be touched or modified by this step.</li><br/>
			<li>shutdown fhem</li><br/>
			<li>restart fhem with keyword configDB<br/><br/>
			<ul><code>perl fhem.pl configDB</code></ul></li><br/>
			<b>configDB</b> is a keyword which is recognized by fhem to use database for configuration.<br/>
			<br/>
			<b>That's all.</b> Everything (save, rereadcfg etc) should work as usual.
		</ul>
		<br/><br/>

		<b>Additional functions provided</b><br/>
		<ul><br/>
			A new command <code>configdb</code> is propagated to fhem.<br/>
			This command can be used with different parameters.<br/>
			<br/>

		<li><code>configdb attr [attribute] [value]</code></li><br/>
			Provides the possibility to pass attributes to backend and frontend.<br/>
			<br/>
			<code> configdb attr private 1</code> - set the attribute named 'private' to value 1.<br/>
			<br/>
			<code> configdb attr private</code> - delete the attribute named 'private'<br/>
			<br/>
			<code> configdb attr</code> - show all defined attributes.<br/>
			<br/>
			Currently, only one attribute is supported. If 'private' is set to 1 the user and password info<br/>
			will not be shown in 'configdb info' output.<br/>
<br/>

		<li><code>configdb diff &lt;device&gt; &lt;version&gt;</code></li><br/>
			Compare configuration dataset for device &lt;device&gt; 
			from current version 0 with version &lt;version&gt;<br/>
			Example for valid request:<br/>
			<br/>
			<code>configdb diff telnetPort 1</code><br/>
			<br/>
			will show a result like this:
			<pre>
compare device: telnetPort in current version 0 (left) to version: 1 (right)
+--+--------------------------------------+--+--------------------------------------+
| 1|define telnetPort telnet 7072 global  | 1|define telnetPort telnet 7072 global  |
* 2|attr telnetPort room telnet           *  |                                      |
+--+--------------------------------------+--+--------------------------------------+</pre>

		<li><code>configdb filedelete &lt;Filename&gt;</code></li><br/>
			Delete file from database.<br/>
			<br/>
<br/>

		<li><code>configdb fileexport &lt;targetFilename&gt;</code></li><br/>
			Exports specified fhem file from database into filesystem.<br/>
			Example:<br/>
			<br/>
			<code>configdb fileexport FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb fileimport &lt;sourceFilename&gt;</code></li><br/>
			Imports specified text file from from filesystem into database.<br/>
			Example:<br/>
			<br/>
			<code>configdb fileimport FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb filelist</code></li><br/>
			Show a list with all filenames stored in database.<br/>
			<br/>
<br/>

		<li><code>configdb filemove &lt;sourceFilename&gt;</code></li><br/>
			Imports specified fhem file from from filesystem into database and<br/>
			deletes the file from local filesystem afterwards.<br/>
			Example:<br/>
			<br/>
			<code>configdb filemove FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb fileshow &lt;Filename&gt;</code></li><br/>
			Show content of specified file stored in database.<br/>
			<br/>
<br/>

		<li><code>configdb info</code></li><br/>
			Returns some database statistics<br/>
<pre>
--------------------------------------------------------------------------------
 configDB Database Information
--------------------------------------------------------------------------------
 dbconn: SQLite:dbname=/opt/fhem/configDB.db
 dbuser: 
 dbpass: 
 dbtype: SQLITE
--------------------------------------------------------------------------------
 fhemconfig: 7707 entries

 Ver 0 saved: Sat Mar  1 11:37:00 2014 def: 293 attr: 1248
 Ver 1 saved: Fri Feb 28 23:55:13 2014 def: 293 attr: 1248
 Ver 2 saved: Fri Feb 28 23:49:01 2014 def: 293 attr: 1248
 Ver 3 saved: Fri Feb 28 22:24:40 2014 def: 293 attr: 1247
 Ver 4 saved: Fri Feb 28 22:14:03 2014 def: 293 attr: 1246
--------------------------------------------------------------------------------
 fhemstate: 1890 entries saved: Sat Mar  1 12:05:00 2014
--------------------------------------------------------------------------------
</pre>
Ver 0 always indicates the currently running configuration.<br/>
<br/>

		<li><code>configdb list [device] [version]</code></li><br/>
			Search for device named [device] in configuration version [version]<br/>
			in database archive.<br/>
			Default value for [device] = % to show all devices.<br/>
			Default value for [version] = 0 to show devices from current version.<br/>
			Examples for valid requests:<br/>
			<br/>
			<code>get configDB list</code><br/>
			<code>get configDB list global</code><br/>
			<code>get configDB list '' 1</code><br/>
			<code>get configDB list global 1</code><br/>
		<br/>

		<li><code>configdb recover &lt;version&gt;</code></li><br/>
			Restores an older version from database archive.<br/>
			<code>set configDB recover 3</code> will <b>copy</b> version #3 from database 
			to version #0.<br/>
			Original version #0 will be lost.<br/><br/>
			<b>Important!</b><br/>
			The restored version will <b>NOT</b> be activated automatically!<br/>
			You must do a <code>rereadcfg</code> or - even better - <code>shutdown restart</code> yourself.<br/>
<br/>

		<li><code>configdb reorg [keep]</code></li><br/>
			Deletes all stored versions with version number higher than [keep].<br/>
			Default value for optional parameter keep = 3.<br/>
			This function can be used to create a nightly running job for<br/>
			database reorganisation when called from an at-Definition.<br/>
		<br/>

		<li><code>configdb search <searchTerm> [searchVersion]</code></li><br/>
			Search for specified searchTerm in any given version (default=0)<br/>
<pre>
Example:

configdb search %2286BC%

Result:

search result for: %2286BC% in version: 0 
-------------------------------------------------------------------------------- 
define az_RT CUL_HM 2286BC 
define az_RT_Clima CUL_HM 2286BC04 
define az_RT_Climate CUL_HM 2286BC02 
define az_RT_ClimaTeam CUL_HM 2286BC05 
define az_RT_remote CUL_HM 2286BC06 
define az_RT_Weather CUL_HM 2286BC01 
define az_RT_WindowRec CUL_HM 2286BC03 
attr Melder_FAl peerIDs 00000000,2286BC03, 
attr Melder_FAr peerIDs 00000000,2286BC03, 
</pre>
<br/>

		<li><code>configdb uuid</code></li><br/>
			Returns a uuid that can be used for own purposes.<br/>
<br/>

		</ul>
<br/>
<br/>
		<b>Author's notes</b><br/>
		<br/>
		<ul>
			<li>You can find two template files for datebase and configfile (sqlite only!) for easy installation.<br/>
				Just copy them to your fhem installation directory (/opt/fhem) and have fun.</li>
			<br/>
			<li>The frontend option "Edit files"-&gt;"config file" will be removed when running configDB.</li>
			<br/>
			<li>Please be patient when issuing a "save" command 
			(either manually or by clicking on "save config").<br/>
			This will take some moments, due to writing version informations.<br/>
			Finishing the save-process will be indicated by a corresponding message in frontend.</li>
			<br/>
			<li>There still will be some more (planned) development to this extension, 
			especially regarding some perfomance issues.</li>
			<br/>
			<li>Have fun!</li>
		</ul>

	</ul>

=end html

=begin html_DE

<a name="configdb"></a>
<h3>configdb</h3>
	<ul>
		Seit version 5079 unterst&uuml;tzt fhem die Verwendung einer SQL Datenbank zum Abspeichern der kompletten Konfiguration<br/>
		Dadurch kann man auf alle cfg Dateien, includes usw. verzichten und die daraus immer wieder resultierenden Probleme vermeiden.<br/>
		Desweiteren gibt es damit eine Versionierung von Konfigurationen und die M&ouml;glichkeit, 
		jederzeit eine &auml;ltere Version wiederherstellen zu k&ouml;nnen.<br/>
		Der Zugriff auf die Datenbank erfolgt &uuml;ber die perl-eigene Datenbankschnittstelle DBI.<br/>
		<br/>

		<b>Zusammenspiel mit anderen fhem Modulen</b><br/>
		<ul><br/>
			Momentan verwenden die Module<br/>
			<br/>
			<li>02_RSS.pm</li>
			<li>91_eventTypes</li>
			<li>93_DbLog.pm</li>
			<li>95_holiday.pm</li>
			<li>98_SVG.pm</li>
			<br/>
			die configDB, um ihre Konfigurationsdaten von dort zu lesen<br/>
			anstatt aus den bisherigen Konfigurationsdateien im Dateisystem.<br/>
			Hierzu ist es notwendig, die Konfigurationsdateien aus dem Dateisystem in die Datenbank zu importieren.<br/>
			<br/>
			Beispiel:<br/>
			<code>configdb fileimport FHEM/nrw.holiday</code><br/>
			<code>configdb fileimport FHEM/myrss.layout</code><br/>
			<code>configdb fileimport www/gplot/xyz.gplot</code><br/>
			<br/>
			<b>Dies hat keinerlei Auswirkungen auf die Definition der holiday oder RSS Instanzen.</b><br/>
			<br>
			<b>Während einer Migration werden alle in der aktuell bestehenden Konfiguration verwendeten externen<br/>
			Konfigurationsdateien automatisch in die Datenbank importiert.</b></br>
			<br/>
			Jeder Neuimport einer bereits in der Datenbank gespeicherten Datei &uuml;berschreibt die vorherige Datei in der Datenbank.<br/>
			<br/>
		</ul><br/>
<br/>

		<b>Voraussetzungen / Installation</b><br/>
		<ul><br/>
		<li>Bitte das perl Paket Text::Diff installieren, falls noch nicht auf dem System vorhanden.</li><br/>
		<li>Es muss eine SQL Datenbank verf&uuml;gbar sein, untsrst&uuml;tzt werden SQLITE, MYSQL und POSTGRESQLL.</li><br/>
		<li>Das zum Datenbanktype geh&ouml;rende DBD Modul muss in perl installiert sein,<br/>
				f&uuml;r sqlite3 auf einem Debian System z.B. das Paket libdbd-sqlite3-perl</li><br/>
		<li>Eine leere Datenbank muss angelegt werden, z.B. in sqlite3:<br/>
			<pre>
	mba:fhem udo$ sqlite3 configDB.db

	SQLite version 3.7.13 2012-07-17 17:46:21
	Enter ".help" for instructions
	Enter SQL statements terminated with a ";"
	sqlite> pragma auto_vacuum=2;
	sqlite> .quit

	mba:fhem udo$ 
			</pre></li>
		<li>Die ben&ouml;tigten Datenbanktabellen werden automatisch angelegt.</li><br/>
		<li>Eine Konfigurationsdatei f&uuml;r die Verbindung zur Datenbank muss angelegt werden.<br/>
			<br/>
			<b>WICHTIG:</b>
			<ul><br/>
				<li>Diese Datei <b>muss</b> den Namen "configDB.conf" haben</li>
				<li>Diese Datei <b>muss</b> im gleichen Verzeichnis liegen wie fhem.pl und configDB.pm, z.B. /opt/fhem</li>
			</ul>
			<br/>
			<pre>
## f&uuml;r MySQL
################################################################
#%dbconfig= (
#	connection => "mysql:database=configDB;host=db;port=3306",
#	user => "fhemuser",
#	password => "fhempassword",
#);
################################################################
#
## f&uuml;r PostgreSQL
################################################################
#%dbconfig= (
#        connection => "Pg:database=configDB;host=localhost",
#        user => "fhemuser",
#        password => "fhempassword"
#);
################################################################
#
## f&uuml;r SQLite (username and password bleiben bei SQLite leer)
################################################################
#%dbconfig= (
#        connection => "SQLite:dbname=/opt/fhem/configDB.db",
#        user => "",
#        password => ""
#);
################################################################
			</pre></li><br/>
		</ul>

		<b>Aufruf mit einer vollst&auml;ndig neuen fhem Installation</b><br/>
		<ul><br/>
			Sehr einfach... fhem muss lediglich folgendermassen gestartet werden:<br/><br/>
			<ul><code>perl fhem.pl configDB</code></ul><br/>
			<b>configDB</b> ist das Schl&uuml;sselwort, an dem fhem erkennt, <br/>
				dass eine Datenbank f&uuml;r die Konfiguration verwendet werden soll.<br/>
			<br/>
			<b>Das war es schon.</b> Alle Befehle (save, rereadcfg etc) arbeiten wie gewohnt.
		</ul>

		<br/>
		<b>oder:</b><br/>
		<br/>

		<b>&uuml;bertragen einer bestehenden fhem Konfiguration in die Datenbank</b><br/>
		<ul><br/>
			Auch sehr einfach... <br/>
			<br/>
			<li>fhem wird zum letzten Mal mit der fhem.cfg gestartet<br/><br/>
				<ul><code>perl fhem.pl fhem.cfg</code></ul></li><br/>
			<br/>
			<li>Bestehende Konfiguration in die Datenbank &uuml;bertragen<br/><br/>
				<ul><code>configdb migrate</code><br/>
					<br/>
					in die Befehlszeile der fhem-Oberfl&auml;che eingeben</ul><br/></br>
					Nicht die Geduld verlieren! Die Migration eine Weile dauern, speziell bei Mini-Systemen wie<br/>
					RaspberryPi or Beaglebone.<br/>
					Am Ende der Migration wird eine aktuelle Datenbankstatistik angezeigt.<br/>
					Die urspr&uuml;ngliche Konfigurationsdatei wird bei diesem Vorgang nicht angetastet.</li><br/>
			<li>fhem beenden.</li><br/>
			<li>fhem mit dem Schl&uuml;sselwort configDB starten<br/><br/>
			<ul><code>perl fhem.pl configDB</code></ul></li><br/>
			<b>configDB</b> ist das Schl&uuml;sselwort, an dem fhem erkennt, <br/>
				dass eine Datenbank f&uuml;r die Konfiguration verwendet werden soll.<br/>
			<br/>
			<b>Das war es schon.</b> Alle Befehle (save, rereadcfg etc) arbeiten wie gewohnt.
		</ul>
		<br/><br/>

		<b>Zus&auml;tzliche Funktionen</b><br/>
		<ul><br/>
			Es wird ein neuer Befehl <code>configdb</code> bereitgestellt,<br/>
			der mit verschiedenen Parametern aufgerufen werden kann.<br/>
			<br/>

		<li><code>configdb attr [attribute] [value]</code></li><br/>
			Hiermit lassen sich attribute setzen, die das Verhalten von Front- und Backend beeinflussen.<br/>
			<br/>
			<code> configdb attr private 1</code> - setzt das Attribut 'private' auf den Wert 1.<br/>
			<br/>
			<code> configdb attr private</code> - l&ouml;scht das Attribut 'private'<br/>
			<br/>
			<code> configdb attr</code> - zeigt alle gespeicherten Attribute<br/>
			<br/>
			Im Moment ist nur ein Attribut definiert. Wenn 'private' auf 1 gesetzt wird, werden bei 'configdb info' <br/>
			keine Benutzer- und Passwortdaten angezeigt.<br/>
			<br/>
<br/>

		<li><code>configdb diff &lt;device&gt; &lt;version&gt;</code></li><br/>
			Vergleicht die Konfigurationsdaten des Ger&auml;tes &lt;device&gt; aus der aktuellen Version 0 mit den Daten aus Version &lt;version&gt;<br/>
			Beispielaufruf:<br/>
			<br/>
			<code>configdb diff telnetPort 1</code><br/>
			<br/>
			liefert ein Ergebnis &auml;hnlich dieser Ausgabe:
			<pre>
compare device: telnetPort in current version 0 (left) to version: 1 (right)
+--+--------------------------------------+--+--------------------------------------+
| 1|define telnetPort telnet 7072 global  | 1|define telnetPort telnet 7072 global  |
* 2|attr telnetPort room telnet           *  |                                      |
+--+--------------------------------------+--+--------------------------------------+</pre>

		<li><code>configdb filedelete &lt;Dateiname&gt;</code></li><br/>
			L&ouml;scht eine gespeicherte Datei aus der Datenbank.<br/>
			<br/>
<br/>

		<li><code>configdb fileexport &lt;zielDatei&gt;</code></li><br/>
			Schreibt die angegebene Datei aus der Datenbank in das Dateisystem.
			Beispiel:<br/>
			<br/>
			<code>configdb fileexport FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb fileimport &lt;quellDatei&gt;</code></li><br/>
			Liest die angegbene Textdatei aus dem Dateisystem und schreibt den Inhalt in die Datenbank.<br/>
			Beispiel:<br/>
			<br/>
			<code>configdb fileimport FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb filelist</code></li><br/>
			Liefert eine Liste mit allen Namen der gespeicherten Dateien.<br/>
			<br/>
<br/>

		<li><code>configdb filemove &lt;quellDatei&gt;</code></li><br/>
			Liest die angegbene Datei aus dem Dateisystem und schreibt den Inhalt in die Datenbank.<br/>
			Anschliessend wird die Datei aus dem lokalen Dateisystem gel&ouml;scht.<br/>
			Beispiel:<br/>
			<br/>
			<code>configdb filemove FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb fileshow &lt;Dateiname&gt;</code></li><br/>
			Zeigt den Inhalt einer in der Datenbank gespeichert Datei an.<br/>
			<br/>
<br/>

		<li><code>configdb info</code></li><br/>
			Liefert eine Datenbankstatistik<br/>
<pre>
--------------------------------------------------------------------------------
 configDB Database Information
--------------------------------------------------------------------------------
 dbconn: SQLite:dbname=/opt/fhem/configDB.db
 dbuser: 
 dbpass: 
 dbtype: SQLITE
--------------------------------------------------------------------------------
 fhemconfig: 7707 entries

 Ver 0 saved: Sat Mar  1 11:37:00 2014 def: 293 attr: 1248
 Ver 1 saved: Fri Feb 28 23:55:13 2014 def: 293 attr: 1248
 Ver 2 saved: Fri Feb 28 23:49:01 2014 def: 293 attr: 1248
 Ver 3 saved: Fri Feb 28 22:24:40 2014 def: 293 attr: 1247
 Ver 4 saved: Fri Feb 28 22:14:03 2014 def: 293 attr: 1246
--------------------------------------------------------------------------------
 fhemstate: 1890 entries saved: Sat Mar  1 12:05:00 2014
--------------------------------------------------------------------------------
</pre>
Ver 0 bezeichnet immer die aktuell verwendete Konfiguration.<br/>
<br/>

		<li><code>configdb list [device] [version]</code></li><br/>
			Sucht das Ger&auml;t [device] in der Konfiguration der Version [version]<br/>
			in der Datenbank.<br/>
			Standardwert f&uuml;r [device] = % um alle Ger&auml;te anzuzeigen<br/>
			Standardwert f&uuml;r [version] = 0 um Ger&auml;te in der aktuellen Version anzuzeigen.<br/>
			Beispiele f&uuml;r g&uuml;ltige Aufrufe:<br/>
			<br/>
			<code>configdb list</code><br/>
			<code>configdb list global</code><br/>
			<code>configdb list '' 1</code><br/>
			<code>configdb list global 1</code><br/>
		<br/>

		<li><code>configdb recover &lt;version&gt;</code></li><br/>
			Stellt eine &auml;ltere Version aus dem Datenbankarchiv wieder her.<br/>
			<code>set configDB recover 3</code>  <b>kopiert</b> die Version #3 aus der Datenbank 
			zur Version #0.<br/>
			Die urspr&uuml;ngliche Version #0 wird dabei gel&ouml;scht.<br/><br/>
			<b>Wichtig!</b><br/>
			Die zur&uuml;ckgeholte Version wird <b>NICHT</b> automatisch aktiviert!<br/>
			Ein <code>rereadcfg</code> oder - besser - <code>shutdown restart</code> muss manuell erfolgen.<br/>
		<br/>
		<br/>

		<li><code>configdb reorg [keep]</code></li><br/>
			L&ouml;scht alle gespeicherten Konfigurationen mit Versionsnummern gr&ouml;&szlig;er als [keep].<br/>
			Standardwert f&uuml;r den optionalen Parameter keep = 3.<br/>
			Mit dieser Funktion l&auml;&szlig;t sich eine n&auml;chtliche Reorganisation per at umsetzen.<br/>
		<br/>

		<li><code>configdb search <suchBegriff> [inVersion]</code></li><br/>
			Sucht nach dem Suchbegriff in der angegeben Konfigurationsversion (default=0)<br/>
<pre>
Beispiel:

configdb search %2286BC%

Ergebnis:

search result for: %2286BC% in version: 0 
-------------------------------------------------------------------------------- 
define az_RT CUL_HM 2286BC 
define az_RT_Clima CUL_HM 2286BC04 
define az_RT_Climate CUL_HM 2286BC02 
define az_RT_ClimaTeam CUL_HM 2286BC05 
define az_RT_remote CUL_HM 2286BC06 
define az_RT_Weather CUL_HM 2286BC01 
define az_RT_WindowRec CUL_HM 2286BC03 
attr Melder_FAl peerIDs 00000000,2286BC03, 
attr Melder_FAr peerIDs 00000000,2286BC03, 
</pre>
<br/>

		<li><code>configdb uuid</code></li><br/>
			Liefert eine uuid, die man f&uuml;r eigene Zwecke verwenden kann.<br/>
		<br/>

		<b>Hinweise</b><br/>
		<br/>
		<ul>
			<li>Im Verzeichnis contrib/configDB befinden sich zwei Vorlagen f&uuml;r Datenbank und Konfiguration,<br/>
				die durch einfaches Kopieren in das fhem Verzeichnis sofort verwendet werden k&ouml;nnen (Nur f&uuml;r sqlite!).</li>
			<br/>
			<li>Der Men&uuml;punkt "Edit files"-&gt;"config file" wird bei Verwendung von configDB nicht mehr angezeigt.</li>
			<br/>
			<li>Beim Speichern einer Konfiguration nicht ungeduldig werden (egal ob manuell oder durch Klicken auf "save config")<br/>
				Durch das Schreiben der Versionsinformationen dauert das ein paar Sekunden.<br/>
				Der Abschluss des Speichern wird durch eine entsprechende Meldung angezeigt.</li>
			<br/>
			<li>Diese Erweiterung wird laufend weiterentwickelt. Speziell an der Verbesserung der Performance wird gearbeitet.</li>
			<br/>
			<li>Viel Spass!</li>
		</ul>

	</ul>
</ul>

=end html_DE

=cut
