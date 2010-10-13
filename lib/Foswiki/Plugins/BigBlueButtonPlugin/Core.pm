package Foswiki::Plugins::BigBlueButtonPlugin::Core;

use strict;

require Foswiki::Func;       # The plugins API
require Foswiki::Plugins;    # For the API version

use URI::Escape;
use Digest::SHA1;
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;
use XML::Simple;
use JSON;

# Global variables
our $baseWeb;
our $baseTopic;
our $baseUrl;
our $salt;
our %rooms;

use constant DEBUG => 1;

################################################################################
# writeDebug: print to data/debug.txt when DEBUG is set.
################################################################################
sub writeDebug {
    Foswiki::Func::writeDebug("BigBlueButtonPlugin:Core - $_[0]\n") if DEBUG;
}

################################################################################
# init
#
# Reads configuration settings, establishes a connection to the
# BigBlueButton server, creates the meeting rooms and creates
# a topic in the main web for each meeting room.
################################################################################
sub init {
    ( $baseWeb, $baseTopic ) = @_;

    writeDebug("init: baseWeb=$baseWeb, baseTopic=$baseTopic\n");

    $baseUrl = $Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{baseUrl};
    $salt    = $Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{salt};
    my $conferenceRooms = $Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{rooms};
    writeDebug( "init: configured for conference rooms: "
          . Data::Dumper->Dump($conferenceRooms)
          . "\n" );

    %rooms = ();
    foreach my $confRoom ( @{$conferenceRooms} ) {
        eval { _createRoom( $confRoom->{'name'}, $confRoom->{'password'} ); };
        if ($@) {
            if ( $@ =~ /404/ ) {
                Foswiki::Func::writeWarning(
                    "init: could not communicate with BBB server at $baseUrl. "
                      . "Failed to create conference room $confRoom->{'name'}: $@\n"
                );
            }
            else {
                writeDebug( "init: could not create conference room "
                      . $confRoom->{'name'}
                      . ": $@\n" );
            }
        }
    }

    if (
        !Foswiki::Func::topicExists(
            Foswiki::Func::getMainWebname(),
            "CategoryConferenceRooms"
        )
      )
    {
        my $text = <<EOF;

The conference rooms are accessible from any browser with support for flash. You will need a headset or microphone and a video camera.

Hover over the conference room name or click on it to see who is currently using the conference room and for joining the room.

Conference rooms: 
%SEARCH{"name~'*ConferenceRoom'" excludetopic="%TOPIC%" type="query" scope="topic" nonoise="on" expandvariables="on" format="   * \$percntBBBROOMNAME{ \$topic }\$percnt  "  }%

Conference rooms are automatically created by the System.BigBlueButtonPlugin.

--
EOF
        Foswiki::Func::saveTopic( Foswiki::Func::getMainWebname(),
            "CategoryConferenceRooms", undef, $text, undef );
        writeDebug( "_createRoom: created topic "
              . Foswiki::Func::getMainWebname()
              . ".CategoryConferenceRooms" );
    }
}

################################################################################
# _createURL
#
# Applies BBB's salt security mechanism to construct an authorized url.
################################################################################
sub _createURL {
    my ( $functionName, $parameters ) = @_;

    my $base = $functionName;
    my $args = "";
    for my $key ( keys %{$parameters} ) {
        if ($args) {
            $args = $args . "&";
        }
        $args =
          $args . uri_escape($key) . "=" . uri_escape( $parameters->{$key} );
    }
    $base = $base . $args . $salt;
    my $sha1 = Digest::SHA1::sha1_hex($base);

    return $baseUrl . "/" . $functionName . "?" . $args . "&checksum=" . $sha1;
}

################################################################################
# _command
#
# POSTs a URL and returns the parsed reply.
################################################################################
sub _command {
    my ($url) = @_;
    my $ua = LWP::UserAgent->new( 'agent' => 'Mozilla/5.0' );
    $ua->timeout(10);
    $ua->env_proxy;

    Foswiki::Func::writeDebug("_command $url\n");
    my $request = HTTP::Request->new( GET => $url );
    my $response = $ua->request($request);
    if ( $response->is_success ) {
        return $response->content;
    }
    else {
        croak $response->status_line;
    }
}

################################################################################
# _createRoom
#
# Creates a room. Creates a topic in the main web for the conference room if
# it does not exsit yet, and contacts BBB to create the room.
################################################################################
sub _createRoom {
    my ( $roomName, $password ) = @_;

    my $roomTopic = $roomName;
    $roomTopic =~ s/\b([a-z])/\u$1/g;
    $roomTopic =~ s/\s*//g;
    $roomTopic = $roomTopic . "ConferenceRoom";

    my $roomUrl =
      Foswiki::Func::getViewUrl( Foswiki::Func::getMainWebname(), $roomTopic );
    my $welcome =
"Welcome to the $roomName conference room. Please go to <a href=\"$roomUrl\">$roomUrl</a> for more details.\n";

    my $reply = _command(
        _createURL(
            'create',
            {
                'name'        => $roomName,
                'meetingID'   => $roomName,
                'attendeePW'  => '1234',
                'moderatorPW' => $password,
                'welcome'     => $welcome,
                'logoutURL'   => $roomUrl
            }
        )
    );

    if (
        !Foswiki::Func::topicExists(
            Foswiki::Func::getMainWebname(), $roomTopic
        )
      )
    {
        my $text = <<EOF;
---++ Conference room $roomName
Current participants are: %BBBROOMDETAILS{$roomName}%

To join: %BBBJOINROOM{$roomName}% 

---+++ Room details:
   * The asterisk meetme room name (audio) is $roomName. If you use meetme, please ensure that /etc/asterisk/bbb_extensions.conf contains 
      * exten => $roomName,1,Playback(conf-placeintoconf)
      * exten => $roomName,n,MeetMe(\${EXTEN},cdMsT)
   * Moderator password is $password

This conference room was automatically created by the System.BigBlueButtonPlugin

--

CategoryConferenceRooms
EOF
        Foswiki::Func::saveTopic( Foswiki::Func::getMainWebname(),
            $roomTopic, undef, $text, undef );
        writeDebug( "_createRoom: created topic "
              . Foswiki::Func::getMainWebname()
              . ".$roomTopic" );
    }
    else {
        writeDebug("_createRoom: topic $roomTopic already exists.");
    }

    $rooms{$roomName} = {
        'password' => $password,
        'url'      => Foswiki::Func::getMainWebname() . "." . $roomTopic
    };
    writeDebug(
        "_createRoom: rooms =" . Data::Dumper->Dump( [ \%rooms ] ) . "\n" );
}

################################################################################
# _listRooms
#
# Returns an hash of room names => urls
################################################################################
sub _listRooms {
    return map { $_ => $rooms{$_}{'url'} } keys %rooms;
}

################################################################################
# _getPeopleInRoom
#
#
################################################################################
sub _getPeopleInRoom {

    # Returns an array of participants names for the given room.
    # Returns undef if the room does not exist.
    my ($room) = @_;

    return undef unless ( exists $rooms{$room} );

    my @participants = ();
    my $response     = _command(
        _createURL(
            'getMeetingInfo',
            { 'meetingID' => $room, 'password' => $rooms{$room}{'password'} }
        )
    );
    Foswiki::Func::writeDebug(
        "_getPeopleInRoom: " . Data::Dumper->Dump( [$response] ) . "\n" );
    my $ref = XMLin($response);

    if (   exists $ref->{'attendees'}
        && exists $ref->{'attendees'}->{'attendee'} )
    {

# 'attendee' is either a list of hashes (> 1 attendee) or just a hash (1 attendee)
        if ( ref( $ref->{'attendees'}->{'attendee'} ) eq 'ARRAY' ) {
            foreach my $attendee ( @{ $ref->{'attendees'}->{'attendee'} } ) {
                push @participants, $attendee->{'fullName'};
            }
        }
        else {
            push @participants, $ref->{'attendees'}->{'attendee'}->{'fullName'};
        }
    }

    Foswiki::Func::writeDebug(
        "_getPeopleInRoom return @participants for room $room.\n");
    return @participants;
}

################################################################################
# _getJoinRoomUrl
#
# Returns a URL that will let you join the given room with the given name,
# or undef if the room does not exist.
################################################################################
sub _getJoinRoomUrl {
    my ( $room, $name ) = @_;

    return undef unless exists $rooms{$room};
    return _createURL(
        'join',
        {
            'fullName'  => $name,
            'meetingID' => $room,
            'password'  => $rooms{$room}{'password'}
        }
    );
}

1;
