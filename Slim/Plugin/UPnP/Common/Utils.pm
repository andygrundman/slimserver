package Slim::Plugin::UPnP::Common::Utils;

### TODO
#
# Add pv namespace to trackDetails, xmlns:pv="http://www.pv.com/pvns/", for example:
# <pv:rating>2</pv:rating>
# <pv:playcount>2016</pv:playcount>
# <pv:lastPlayedTime>2010-02-10T16:02:37</pv:lastPlayedTime>
# <pv:addedTime>1261090276</pv:addedTime>
# <pv:modificationTime>1250180640</pv:modificationTime>

use strict;

use Scalar::Util qw(blessed);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Exporter::Lite;
our @EXPORT_OK = qw(xmlEscape xmlUnescape secsToHMS hmsToSecs absURL trackDetails);

my $log   = logger('plugin.upnp');
my $prefs = preferences('server');

sub xmlEscape {
	my $text = shift;
	
	if ( $text =~ /[\&\<\>'"]/) {
		$text =~ s/&/&amp;/go;
		$text =~ s/</&lt;/go;
		$text =~ s/>/&gt;/go;
		$text =~ s/'/&apos;/go;
		$text =~ s/"/&quot;/go;
	}
	
	return $text;
}

sub xmlUnescape {
	my $text = shift;
	
	if ( $text =~ /[\&]/) {
		$text =~ s/&amp;/&/go;
		$text =~ s/&lt;/</go;
		$text =~ s/&gt;/>/go;
		$text =~ s/&apos;/'/go;
		$text =~ s/&quot;/"/go;
	}
	
	return $text;
}

# seconds to H:MM:SS[.F+]
sub secsToHMS {
	my $secs = shift;
	
	my $elapsed = sprintf '%d:%02d:%02d', int($secs / 3600), int($secs / 60), $secs % 60;
	
	if ( $secs =~ /(\.\d+)$/ ) {
		my $frac = sprintf( '%.3f', $1 );
		$frac =~ s/^0//;
		$elapsed .= $frac;
	}
	
	return $elapsed;
}

# H:MM:SS[.F+] to seconds
sub hmsToSecs {
	my $hms = shift;
	
	my ($h, $m, $s) = split /:/, $hms;
	
	return ($h * 3600) + ($m * 60) + $s;
}

sub absURL {
	my $path = shift;
	
	my $hostport = Slim::Utils::Network::serverAddr() . ':' . $prefs->get('httpport');
	
	return xmlEscape("http://${hostport}${path}");
}

sub trackDetails {
	my ( $track, $filter ) = @_;
	
	my $filterall = ($filter eq '*');
	
	if ( blessed($track) ) {
		# Convert from a Track object
		# Going through a titles query request will be the fastest way, to avoid slow DBIC joins and such.
		my $request = Slim::Control::Request->new( undef, [ 'titles', 0, 1, 'track_id:' . $track->id, 'tags:AGldyorfTIct' ] );
		$request->execute();
		if ( $request->isStatusError ) {
			$log->error('Cannot convert Track object to hashref: ' . $request->getStatusText);
			return '';
		}
		
		my $results = $request->getResults;
		if ( $results->{count} != 1 ) {
			$log->error('Cannot convert Track object to hashref: no track found');
			return '';
		}
		
		$track = $results->{titles_loop}->[0];
	}
	
	my $xml;
	
	my @albumartists = split /, /, $track->{albumartist};
	my @artists      = split /, /, $track->{artist};
	
	my $primary_artist = $albumartists[0] ? $albumartists[0] : $artists[0];
	
	# This supports either track data from CLI results or _getTagDataForTracks, thus
	# the checks for alternate hash keys
	
	$xml .= '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
		. '<dc:title>' . xmlEscape($track->{title} || $track->{'tracks.title'}) . '</dc:title>';
	
	if ( $filterall || $filter =~ /dc:creator/ ) {
		$xml .= '<dc:creator>' . xmlEscape($primary_artist) . '</dc:creator>';
	}
	
	if ( $filterall || $filter =~ /upnp:album/ ) {
		$xml .= '<upnp:album>' . xmlEscape($track->{album} || $track->{'albums.title'}) . '</upnp:album>';
	}
	
	my %roles;
	map { push @{$roles{albumartist}}, $_ } @albumartists;
	map { push @{$roles{artist}}, $_ } @artists;
	map { push @{$roles{composer}}, $_ } split /, /, $track->{composer};
	map { push @{$roles{conductor}}, $_ } split /, /, $track->{conductor};
	map { push @{$roles{band}}, $_ } split /, /, $track->{band};
	map { push @{$roles{trackartist}}, $_ } split /, /, $track->{trackartist};
	
	my $artistfilter = ( $filterall || $filter =~ /upnp:artist/ );
	my $contribfilter = ( $filterall || $filter =~ /dc:contributor/ );
	while ( my ($role, $names) = each %roles ) {
		for my $artist ( @{$names} ) {
			my $x = xmlEscape($artist);
			if ( $artistfilter ) { $xml .= "<upnp:artist role=\"${role}\">${x}</upnp:artist>"; }
			if ( $contribfilter ) { $xml .= "<dc:contributor>${x}</dc:contributor>"; }
		}
	}
	
	if ( my $tracknum = ($track->{tracknum} || $track->{'tracks.tracknum'}) ) {
		if ( $filterall || $filter =~ /upnp:originalTrackNumber/ ) {
			$xml .= "<upnp:originalTrackNumber>${tracknum}</upnp:originalTrackNumber>";
		}
	}
	
	if ( my $date = ($track->{year} || $track->{'tracks.year'}) ) {
		if ( $filterall || $filter =~ /dc:date/ ) {
			$xml .= "<dc:date>${date}-01-01</dc:date>"; # DLNA requires MM-DD values
		}
	}
	
	if ( my @genres = split /, /, $track->{genres} ) {
		if ( $filterall || $filter =~ /upnp:genre/ ) {
			for my $genre ( @genres ) {
				$xml .= '<upnp:genre>' . xmlEscape($genre) . '</upnp:genre>';
			}
		}
	}
	
	if ( my $coverid = ($track->{coverid} || $track->{'tracks.coverid'}) ) {
		if ( $filterall || $filter =~ /upnp:albumArtURI/ ) {
			$xml .= '<upnp:albumArtURI>' . absURL("/music/$coverid/cover") . '</upnp:albumArtURI>';
		}
	}
	
	if ( $filterall || $filter =~ /res/ ) {
		my ($bitrate) = $track->{bitrate} =~ /^(\d+)/;
		if ( !$bitrate && $track->{'tracks.bitrate'} ) {
			$bitrate = $track->{'tracks.bitrate'} / 1000;
		}
		
		# We need to provide a <res> for the native file, as well as compatability formats via transcoding
		my $native_type = $Slim::Music::Info::types{ $track->{type} || $track->{'tracks.content_type'} };
		my @other_types;
		if ( $native_type ne 'audio/mpeg' ) {
			push @other_types, 'audio/mpeg';
			# XXX audio/L16
		}
		
		for my $type ( $native_type, @other_types ) {
			$xml .= '<res protocolInfo="http-get:*:' . $type . ':*"';
		
			if ( ($filterall || $filter =~ /res\@size/) && $type eq $native_type ) {
				# Size only available for native type
				$xml .= ' size="' . ($track->{filesize} || $track->{'tracks.filesize'}) . '"';
			}
			if ( $filterall || $filter =~ /res\@duration/ ) {
				$xml .= ' duration="' . secsToHMS($track->{duration} || $track->{'tracks.secs'}) . '"';
			}
			if ( ($filterall || $filter =~ /res\@bitrate/) && $type eq $native_type ) {
				# Bitrate only available for native type
				$xml .= ' bitrate="' . (($bitrate * 1000) / 8) . '"'; # yes, it's bytes/second for some reason
			}

			if ( my $bps = ($track->{samplesize} || $track->{'tracks.samplesize'}) ) {
				if ( $filterall || $filter =~ /res\@bitsPerSample/ ) {
					$xml .= " bitsPerSample=\"${bps}\"";
				}
			}

			if ( $filterall || $filter =~ /res\@sampleFrequency/ ) {
				$xml .= ' sampleFrequency="' . ($track->{samplerate} || $track->{'tracks.samplerate'}) . '"';
			}
			
			my $ext = Slim::Music::Info::mimeToType($type);
			
			if ( $ext eq 'mp3' ) {
				$ext = 'mp3?bitrate=320';
			}
		
			$xml .= '>' . absURL('/music/' . ($track->{id} || $track->{'tracks.id'}) . '/download.' . $ext) . '</res>';
		}
	}
	
	return $xml;
}

1;