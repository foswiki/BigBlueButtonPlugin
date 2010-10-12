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
our $SHORTDESCRIPTION = 'Supports wiki meeting rooms by integrating web conferencing from BigBlueButton.org';
our $NO_PREFS_IN_TOPIC = 1;

# Global variables
our $baseTopic;
our $baseWeb;
our $json;

sub initPlugin {
    ($baseTopic, $baseWeb) = @_;

    # check for Plugins.pm versions
    if( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
                                     __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerTagHandler( 'BBBJOINROOM', \&_JOINROOM );
    Foswiki::Func::registerTagHandler( 'BBBROOMDETAILS', \&_ROOMDETAILS );
    Foswiki::Func::registerTagHandler( 'BBBROOMNAME', \&_ROOMNAME );

    Foswiki::Func::registerRESTHandler('listRooms', \&_RESTlistRooms);
    Foswiki::Func::registerRESTHandler('getJoinRoomUrl', \&_RESTgetJoinRoomURL);
    Foswiki::Func::registerRESTHandler('joinRoom', \&_RESTjoinRoom);
    Foswiki::Func::registerRESTHandler('getPeopleInRoom', \&_RESTgetPeopleInRoom);

    $json = JSON->new->allow_nonref;

    require Foswiki::Plugins::BigBlueButtonPlugin::Core;
    Foswiki::Plugins::BigBlueButtonPlugin::Core::init($baseWeb, $baseTopic);

    return 1;
}


sub _JOINROOM {
    # Returns a URL that will let the currently logged in user
    # join the specified room.
    # Example: %BBBJOINROOM{Daisy}%

    my ($session, $params, $theTopic, $theWeb) = @_;
    my $roomName = $params->{_DEFAULT};
    my $userName = Foswiki::Func::getWikiUserName();
    return Foswiki::Func::renderText("[[" . Foswiki::Plugins::BigBlueButtonPlugin::Core::_getJoinRoomUrl($roomName, $userName)  .
                                      "][join $roomName conference room as $userName]]");
}
sub _ROOMDETAILS {
    # Returns a list of people in the specified room.
    # Example: %BBBROOMDETAILS{Daisy}%
    my ($session, $params, $theTopic, $theWeb) = @_;

    my $roomName = $params->{_DEFAULT};
    my @people = Foswiki::Plugins::BigBlueButtonPlugin::Core::_getPeopleInRoom($roomName);
    return Foswiki::Func::renderText(join(", ", @people));
}

sub _ROOMNAME {
    # Given a topic name like GullConferenceRoom,
    # returns link to that topic with tooltips.
    my ($session, $params, $theTopic, $theWeb) = @_;

    # %SEARCH{"name~'*ConferenceRoom'" excludetopic="%TOPIC%" type="query"
    #         scope="topic" nonoise="on" expandvariables="on" format="   * $percntBBBROOMNAME{ $topic }$percnt  "  }%

    my $roomName = $params->{_DEFAULT};
    $roomName =~ s/^(.*)ConferenceRoom$/$1/g;
    my %rooms = Foswiki::Plugins::BigBlueButtonPlugin::Core::_listRooms();

    Foswiki::Func::writeDebug("_ROOMNAME called for room $roomName (original $params->{_DEFAULT}).\n");
    Foswiki::Func::writeDebug("_ROOMNAME rooms = " . Data::Dumper->Dump([ \%rooms ]) . "\n");
    return "" unless exists $rooms{$roomName};

    eval 'require Foswiki::Plugins::ToolTipPlugin';
    if ($@) {
        return "[[" . $rooms{$roomName} . "][$roomName conference room]]";
    } else {
        my $tipParams = { 'TITLE' => "$roomName conference room" ,
                          'URL' => Foswiki::Func::getViewUrl(split(/\./, $rooms{$roomName})),
                          'INCLUDE' => $rooms{$roomName},
                          'STICKY' => "true",
                          'WIDTH' => "400",
                          '_RAW' => '$roomName' };
        my $text = Foswiki::Plugins::ToolTipPlugin::_TOOLTIP($session, $tipParams, $theTopic, $theWeb);
        $text = $text . "$roomName conference room";
        $text = $text . Foswiki::Plugins::ToolTipPlugin::_TOOLTIP($session, { 'END' },$theTopic, $theWeb);
        return $text;
    }
}
sub _RESTgetJoinRoomURL {
    # Returns the url that will send the given person to the given room.
    # Parameters: room
    my ($session, $plugin, $functionname, $response) = @_;

    my $query = $session->{'request'};
    my $userName = $session->{'remoteUser'};
    my $room = $query->{'param'}->{'room'}[0];

    my $url = Foswiki::Plugins::BigBlueButtonPlugin::Core::_getJoinRoomUrl($room, $userName);

    my $r = { 'meetingRoomName' => $room, 'userName' => $userName, 'joinURL' => $url };

    $response->print($json->pretty->encode($r));
    return;
}

sub _RESTjoinRoom {
    # Redirects the calller to the url that will send the given person to the given room.
    # Parameters: room
    my ($session, $plugin, $functionname, $response) = @_;

    my $query = $session->{'request'};
    my $userName = $session->{'remoteUser'};
    my $room = $query->{'param'}->{'room'}[0];

    my $url = Foswiki::Plugins::BigBlueButtonPlugin::Core::_getJoinRoomUrl($room, $userName);

    return Foswiki::Func::redirectCgiQuery(undef, $url, 0);
}

sub _RESTgetPeopleInRoom {
    # Returns a list of current participants.
    my ($session, $plugin, $functionname, $response) = @_;

    my $query = $session->{'request'};
    my $room = $query->{'param'}->{'room'}[0];

    my $r = { 'meetingRoomName' => $room, 'participants' => [ Foswiki::Plugins::BigBlueButtonPlugin::Core::_getPeopleInRoom($room) ] };

    $response->print($json->pretty->encode($r));

    return;
}
sub _RESTlistRooms {
    my ($session, $plugin, $functionName, $response) = @_;
    # Returns a list of meeting rooms, with room name and list of current participants.

    my $r = { 'meetingRooms' => [] };
    foreach my $room (Foswiki::Plugins::BigBlueButtonPlugin::Core::_listRooms()) {
        push @{ $r->{'meetingRooms'} }, { 'meetingRoomName'=> $room, 'participants' => [ Foswiki::Plugins::BigBlueButtonPlugin::Core::_getPeopleInRoom($room) ]};
    }

    $response->print($json->pretty->encode($r));

    return;
}
1;
__END__
