package Foswiki::Plugins::BigBlueButtonPlugin::BBBServer;

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

use constant DEBUG => 1;

################################################################################
# writeDebug: print to working/logs/debug.txt when DEBUG is set.
################################################################################
sub writeDebug {
    Foswiki::Func::writeDebug("BigBlueButtonPlugin::BBBServer - $_[0]\n")
      if DEBUG;
}

################################################################################
# Constructor for a new BBB server.
#
# Reads configuration settings but does not communicate with the server.
################################################################################
sub new {
    my ($class) = @_;
    my $this = {};

    $this->{'baseUrl'} = $Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{baseUrl};
    $this->{'salt'}    = $Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{salt};
    $this->{'conferenceRooms'} =
      $Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{rooms};

    Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
            "new: configured for conference rooms: "
          . Data::Dumper->Dump( $this->{'conferenceRooms'} )
          . "\n" );

    $this->{'rooms'} = ();

    return bless( $this, $class );
}

################################################################################
# Inializes a BBB server by establishing a connection to the server,
# creating all meeting rooms and creating the CategoryConferenceRooms topic in
# the main web for each.
################################################################################
sub initialize {
    my ($this) = @_;

    foreach my $confRoom ( @{ $this->{'conferenceRooms'} } ) {
        eval {
            $this->createRoom(
                $confRoom->{'name'},
                $confRoom->{'audioBridge'},
                $confRoom->{'password'}
            );
        };
        if ($@) {
            if ( $@ =~ /404/ ) {
                Foswiki::Func::writeWarning(
"initialize: could not communicate with BBB server at $this->{'baseUrl'}. "
                      . "Failed to create conference room $confRoom->{'name'}: $@\n"
                );
            }
            else {
                Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
                        "initialize: could not create conference room "
                      . $confRoom->{'name'}
                      . ": $@\n" );
            }
        }
    }

    if (
        !Foswiki::Func::topicExists(
            $Foswiki::cfg{UsersWebName},
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
        Foswiki::Func::saveTopic( $Foswiki::cfg{UsersWebName},
            "CategoryConferenceRooms", undef, $text, undef );
        Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
                "initialize: created topic "
              . $Foswiki::cfg{UsersWebName}
              . ".CategoryConferenceRooms" );
    }
}

################################################################################
# Destroys all rooms and removes the CategoryConferenceRooms topic in the
# main web.
################################################################################
sub cleanup {
    my ($this) = @_;

    for my $room ( keys %{ $this->{'rooms'} } ) {
        $this->destroyRoom($room);
    }

    if (
        Foswiki::Func::topicExists(
            $Foswiki::cfg{UsersWebName},
            "CategoryConferenceRooms"
        )
      )
    {
        Foswiki::Func::moveTopic(
            $Foswiki::cfg{UsersWebName}, "CategoryConferenceRooms",
            $Foswiki::cfg{TrashWebName}, "OldConferenceRooms"
        );
    }
}

################################################################################
# _createURL
#
# Applies BBB's salt security mechanism to construct an authorized url.
################################################################################
sub _createURL {
    my ( $this, $functionName, $parameters ) = @_;

    my $base = $functionName;
    my $args = "";
    for my $key ( keys %{$parameters} ) {
        if ($args) {
            $args = $args . "&";
        }
        $args =
          $args . uri_escape($key) . "=" . uri_escape( $parameters->{$key} );
    }
    $base = $base . $args . $this->{'salt'};
    my $sha1 = Digest::SHA1::sha1_hex($base);

    return
        $this->{'baseUrl'} . "/"
      . $functionName . "?"
      . $args
      . "&checksum="
      . $sha1;
}

################################################################################
# _command
#
# Static command that POSTs a URL and returns the parsed reply.
################################################################################
sub _command {
    my ($url) = @_;

    my $ua = LWP::UserAgent->new( 'agent' => 'Mozilla/5.0' );
    $ua->timeout(10);
    $ua->env_proxy;

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
# createRoom
#
# Creates a room. Creates a topic in the main web for the conference room if
# it does not exsit yet, and contacts BBB to create the room.
################################################################################
sub createRoom {
    my ( $this, $roomName, $audioBridge, $password ) = @_;

    my $roomTopic = $roomName;
    $roomTopic =~ s/\b([a-z])/\u$1/g;
    $roomTopic =~ s/\s*//g;
    $roomTopic = $roomTopic . "ConferenceRoom";

    my $roomUrl =
      Foswiki::Func::getViewUrl( $Foswiki::cfg{UserWebName}, $roomTopic );
    my $welcome =
"Welcome to the $roomName conference room. Please go to <a href=\"$roomUrl\">$roomUrl</a> for more details.\n";

    my $reply = Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::_command(
        $this->_createURL(
            'create',
            {
                'name'        => $roomName,
                'meetingID'   => $roomName,
                'attendeePW'  => '1234',
                'moderatorPW' => $password,
                'welcome'     => $welcome,
                'voiceBridge' => $audioBridge,
                'logoutURL'   => $roomUrl
            }
        )
    );

    if (
        !Foswiki::Func::topicExists( $Foswiki::cfg{UsersWebName}, $roomTopic ) )
    {
        my $text = <<EOF;
---++ Conference room $roomName
Current participants are: %BBBROOMDETAILS{$roomName}%

To join: %BBBJOINROOM{$roomName}% 

---+++ Room details:
   * This room's voice bridge (for asterisk) is $audioBridge.
   * Moderator password is $password

This conference room was automatically created by the System.BigBlueButtonPlugin

--

CategoryConferenceRooms
EOF
        Foswiki::Func::saveTopic( $Foswiki::cfg{UsersWebName},
            $roomTopic, undef, $text, undef );
        Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
                "createRoom: created topic "
              . $Foswiki::cfg{UsersWebName}
              . ".$roomTopic" );
    }
    else {
        Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
                "createRoom: topic "
              . $Foswiki::cfg{UsersWebName}
              . ".$roomTopic already exists." );
    }

    $this->{'rooms'}{$roomName} = {
        'password' => $password,
        'topic'    => $roomTopic,
        'url'      => $Foswiki::cfg{UsersWebName} . "." . $roomTopic
    };
    Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
            "createRoom: rooms ="
          . Data::Dumper->Dump( [ \$this->{'rooms'} ] )
          . "\n" );
}

################################################################################
# destroyRoom
#
# Tells the server to end the conference corresponding to this room
# and deletes the room topic from mainWeb.
################################################################################
sub destroyRoom {
    my ( $this, $roomName ) = @_;

    return unless ( exists $this->{'rooms'}{$roomName} );

    my $reply = Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::_command(
        $this->_createURL(
            'end',
            {
                'meetingID' => $roomName,
                'password'  => $this->{'rooms'}{$roomName}->{'password'}
            }
        )
    );

    if (
        Foswiki::Func::topicExists(
            $Foswiki::cfg{UsersWebName},
            $this->{'rooms'}{$roomName}->{'topic'}
        )
      )
    {
        Foswiki::Func::moveTopic(
            $Foswiki::cfg{UsersWebName},
            $this->{'rooms'}{$roomName}->{'topic'},
            $Foswiki::cfg{TrashWebName},
            $this->{'rooms'}{$roomName}->{'topic'}
        );
    }

    delete $this->{'rooms'}{$roomName};
    Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
        "destroyRoom: destroyed room $roomName \n");
}

################################################################################
# listRooms
#
# Returns an hash of room names => urls
################################################################################
sub listRooms {
    my ($this) = @_;

    return
      map { $_ => $this->{'rooms'}{$_}->{'url'} } keys %{ $this->{'rooms'} };
}

################################################################################
# getPeopleInRoom
#
#
################################################################################
sub getPeopleInRoom {

    # Returns an array of participants names for the given room.
    # Returns undef if the room does not exist.
    my ( $this, $roomName ) = @_;

    return undef unless ( exists $this->{'rooms'}{$roomName} );

    my @participants = ();
    my $response = Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::_command(
        $this->_createURL(
            'getMeetingInfo',
            {
                'meetingID' => $roomName,
                'password'  => $this->{'rooms'}{$roomName}->{'password'}
            }
        )
    );
    Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
        "getPeopleInRoom: " . Data::Dumper->Dump( [$response] ) . "\n" );
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

    Foswiki::Plugins::BigBlueButtonPlugin::BBBServer::writeDebug(
        "getPeopleInRoom return @participants for room $roomName.\n");
    return @participants;
}

################################################################################
# getJoinRoomUrl
#
# Returns a URL that will let you join the given room with the given name,
# or undef if the room does not exist.
################################################################################
sub getJoinRoomUrl {
    my ( $this, $roomName, $userName ) = @_;

    return undef unless exists $this->{'rooms'}{$roomName};
    return $this->_createURL(
        'join',
        {
            'fullName'  => $userName,
            'meetingID' => $roomName,
            'password'  => $this->{'rooms'}{$roomName}->{'password'}
        }
    );
}

1;
