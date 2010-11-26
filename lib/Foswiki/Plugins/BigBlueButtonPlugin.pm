# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

=pod

---+ package Foswiki::Plugins::BigBlueButtonPlugin

=cut

package Foswiki::Plugins::BigBlueButtonPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version

#use Data::Dumper;
use JSON;

our $VERSION = '$Rev: 8536 $';
our $RELEASE = '1.0.0';
our $SHORTDESCRIPTION =
'Supports wiki meeting rooms by integrating web conferencing from BigBlueButton.org';
our $NO_PREFS_IN_TOPIC = 1;

# Global variables
our $baseTopic;
our $baseWeb;

use vars qw( $BBBServer $json );

################################################################################
sub initPlugin {
    ( $baseTopic, $baseWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerTagHandler( 'BBBJOINROOM',    \&_JOINROOM );
    Foswiki::Func::registerTagHandler( 'BBBROOMDETAILS', \&_ROOMDETAILS );
    Foswiki::Func::registerTagHandler( 'BBBROOMNAME',    \&_ROOMNAME );

    Foswiki::Func::registerRESTHandler( 'listRooms', \&_RESTlistRooms );
    Foswiki::Func::registerRESTHandler( 'getJoinRoomUrl',
        \&_RESTgetJoinRoomURL );
    Foswiki::Func::registerRESTHandler( 'joinRoom', \&_RESTjoinRoom );
    Foswiki::Func::registerRESTHandler( 'getPeopleInRoom',
        \&_RESTgetPeopleInRoom );

    $json = JSON->new->allow_nonref;

    Foswiki::Func::writeDebug("BigBlueButtonPlugin initialized.");

    return 1;
}

###############################################################################
sub finishPlugin {
    return unless $BBBServer;

    # We don't want to clean up all rooms and re-create them in
    # non-persistent perl mode.
    #$BBBServer->cleanup();
}

################################################################################
sub init {
    return if $BBBServer;

    eval 'use Foswiki::Plugins::BigBlueButtonPlugin::BBBServer';
    if ($@) {
        Foswiki::Func::writeWarning($@);
        print STDERR $@;
    }
    else {
        $BBBServer = new Foswiki::Plugins::BigBlueButtonPlugin::BBBServer();
        $BBBServer->initialize();
    }
}

################################################################################
sub _JOINROOM {

  # Returns a URL that will let the currently logged in user
  # join the specified room.
  # Example: %BBBJOINROOM{Daisy}%
  # When called with an emtpy room name, returns the list of URLs for all rooms.

    my ( $session, $params, $theTopic, $theWeb ) = @_;
    init();

    my $roomName = $params->{_DEFAULT};
    my $userName = Foswiki::Func::getWikiUserName();

    if ( $roomName == "" ) {
        my @roomNames = $BBBServer->listRooms();

        my @rooms = ();
        if ( defined @roomNames ) {
            foreach my $room (@roomNames) {
                my $url = $BBBServer->getJoinRoomUrl( $room, $userName );
                if ( defined $url ) {
                    push @rooms,
                      Foswiki::Func::renderText( "[[" 
                          . $url
                          . "][join $room conference room as $userName]]" );
                }
            }
        }
        return join( ", ", @rooms );
    }
    else {
        my $url = $BBBServer->getJoinRoomUrl( $roomName, $userName );
        if ( defined $url ) {
            return Foswiki::Func::renderText( "[[" 
                  . $url
                  . "][join $roomName conference room as $userName]]" );
        }
        else {
            return "No such room $roomName.";
        }
    }
}

################################################################################
sub _ROOMDETAILS {

    # Returns a list of people in the specified room.
    # Example: %BBBROOMDETAILS{Daisy}%
    my ( $session, $params, $theTopic, $theWeb ) = @_;
    init();

    my $roomName = $params->{_DEFAULT};
    my @people   = $BBBServer->getPeopleInRoom($roomName);
    if ( defined @people ) {
        return Foswiki::Func::renderText( join( ", ", @people ) );
    }
    else {
        return "";
    }
}

################################################################################
sub _ROOMNAME {

    # Given a topic name like GullConferenceRoom,
    # returns link to that topic with tooltips.
    my ( $session, $params, $theTopic, $theWeb ) = @_;
    init();

    my $roomName = $params->{_DEFAULT};
    $roomName =~ s/^(.*)ConferenceRoom$/$1/g;
    my %rooms = $BBBServer->listRooms();

    return "" unless exists $rooms{$roomName};

    eval 'require Foswiki::Plugins::ToolTipPlugin';
    if ($@) {
        return "[[" . $rooms{$roomName} . "][$roomName conference room]]";
    }
    else {
        my $tipParams = {
            'TITLE' => "$roomName conference room",
            'URL' =>
              Foswiki::Func::getViewUrl( split( /\./, $rooms{$roomName} ) ),
            'INCLUDE' => $rooms{$roomName},
            'STICKY'  => "true",
            'WIDTH'   => "400",
            '_RAW'    => '$roomName'
        };
        my $text =
          Foswiki::Plugins::ToolTipPlugin::_TOOLTIP( $session, $tipParams,
            $theTopic, $theWeb );
        $text = $text . "$roomName conference room";
        $text = $text
          . Foswiki::Plugins::ToolTipPlugin::_TOOLTIP( $session, {'END'},
            $theTopic, $theWeb );
        return $text;
    }
}

################################################################################
sub _RESTgetJoinRoomURL {

    # Returns the url that will send the given person to the given room.
    # Parameters: room
    my ( $session, $plugin, $functionname, $response ) = @_;
    init();

    my $query    = $session->{'request'};
    my $userName = $session->{'remoteUser'};
    my $room     = $query->{'param'}->{'room'}[0];

    my $url = $BBBServer->getJoinRoomUrl( $room, $userName );
    if ( defined $url ) {
        my $r = {
            'meetingRoomName' => $room,
            'userName'        => $userName,
            'joinURL'         => $url
        };

        $response->print( $json->pretty->encode($r) );
    }
    else {
        $response->header( -status => 404 );
    }

    return;
}

################################################################################
sub _RESTjoinRoom {

# Redirects the calller to the url that will send the given person to the given room.
# Parameters: room
    my ( $session, $plugin, $functionname, $response ) = @_;
    init();

    my $query    = $session->{'request'};
    my $userName = $session->{'remoteUser'};
    my $room     = $query->{'param'}->{'room'}[0];

    my $url = $BBBServer->getJoinRoomUrl( $room, $userName );
    if ( defined $url ) {
        return Foswiki::Func::redirectCgiQuery( undef, $url, 0 );
    }
    else {
        $response->header( -status => 404 );
        return;
    }
}

################################################################################
sub _RESTgetPeopleInRoom {

    # Returns a list of current participants.
    my ( $session, $plugin, $functionname, $response ) = @_;
    init();

    my $query = $session->{'request'};
    my $room  = $query->{'param'}->{'room'}[0];

    my $r = {
        'meetingRoomName' => $room,
        'participants'    => [ $BBBServer->getPeopleInRoom($room) ]
    };

    $response->print( $json->pretty->encode($r) );

    return;
}

################################################################################
sub _RESTlistRooms {

# Returns a list of meeting rooms, with room name and list of current participants.
    my ( $session, $plugin, $functionName, $response ) = @_;
    init();

    my $r = { 'meetingRooms' => [] };
    foreach my $room ( $BBBServer->listRooms() ) {
        my @people = $BBBServer->getPeopleInRoom($room);
        if ( defined @people ) {
            push @{ $r->{'meetingRooms'} },
              {
                'meetingRoomName' => $room,
                'participants'    => [@people]
              };
        }
    }

    $response->print( $json->pretty->encode($r) );

    return;
}
1;
__END__
