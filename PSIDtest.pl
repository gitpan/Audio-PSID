eval 'exec perl -w -S $0 ${1+"$@"}'
                if 0;

use Audio::PSID;

$myPSID = new Audio::PSID ("Ala.sid") or die "Whoops!";

@array = $myPSID->getFieldNames();
print "Fieldnames = " . join(' ', @array) . "\n";

print "Name = " . $myPSID->get('name') . "\n";

$myPSID->set(author => 'LaLa',
             name => 'Trallalala',
             copyright => '1999 Hungarian Cracking Crew');

$myPSID->setSpeed(1,1);

my $clock = $myPSID->getClockByName();
print "Clock (video standard) before = $clock\n";

$myPSID->setClockByName('PAL');

my $SIDModel = $myPSID->getSIDModel();
print "SIDModel before = $SIDModel\n";

$myPSID->setSIDModelByName('8580');

$myPSID->alwaysValidateWrite(1);
$myPSID->write("Ala2.sid") or die "Couldn't write!";

$myPSID->read("Ala2.sid") or die "Couldn't open!";

$clock = $myPSID->getClockByName();
print "Clock (video standard) after = $clock\n";

$SIDModel = $myPSID->getSIDModelByName();
print "SIDModel after = $SIDModel\n";
