# ---+ Extensions
# ---++ BigBlueButtonPlugin

# **URL M**
# The url of the BigBlueButton API
$Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{baseUrl} = "http://test-install.blindsidenetworks.com/bigbluebutton";

# **STRING 36 M** 
# Security salt for the BigBlueButton instance declared above.
# See beans.dynamicConferenceService.securitySalt in /var/lib/tomcat6/webapps/bigbluebutton/WEB-INF/classes/bigbluebutton.properties
$Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{salt} = "8cd8ef52e8e101574e400365b55e11a6";

# **PERL**
# The conference rooms you want to create in BigBlueButton. The value should be a perl
# array of hashes, each with 'name', 'audioBridge' and 'password' attributes.
$Foswiki::cfg{Plugins}{BigBlueButtonPlugin}{rooms} = [ { 'name'=>"Daisy", 'audioBridge'=>"71000", 'password'=>"5678" },
                                                       { 'name'=>"Iris", 'audioBridge'=>"71001", 'password'=>"5678" }  ];
