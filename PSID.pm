package Audio::PSID;

require 5;

use Carp;
use strict;
use vars qw($VERSION);
use FileHandle;

$VERSION = "2.00";

# These are the recognized field names for a PSID file. They must appear in
# the order they appear in the PSID file after the first 4 ASCII bytes "PSID".
my (@PSIDfieldNames) = qw(version dataOffset loadAddress initAddress
                          playAddress songs startSong speed name author
                          copyright flags startPage pageLength reserved data);

# Additional data stored in the class that are not part of the PSID file
# format are: FILESIZE, FILENAME, and the implicit REAL_LOAD_ADDRESS.
#
# PADDING is used to hold any extra bytes that may be between the standard
# PSID header and the data (usually happens when dataOffset is more than
# 0x007C).

# Constants for individual fields inside 'flags'.
my $MUSPLAYER_OFFSET = 0; # Bit 0.
my $PLAYSID_OFFSET   = 1; # Bit 1.
my $CLOCK_OFFSET     = 2; # Bits 2-3.
my $SIDMODEL_OFFSET  = 4; # Bits 4-5.

sub new {
    my ($type, $file) = @_;
    my $class = ref($type) || $type;
    my $self = {};

    bless ($self, $class);

    $self->initialize();

    if (defined($file)) {
        # Read errors are taken care of by read().
        $self->read($file);
    }

    $self->{validateWrite} = 0;

    return $self;
}

sub initialize() {
    my ($self) = @_;

    # Initial PSID data.
    $self->{PSIDdata} = {
        version => 2,
        dataOffset => 0x7C,
        loadAddress => 0,
        initAddress => 0,
        playAddress => 0,
        songs => 0,
        startSong => 0,
        speed => 0,
        name => '<?>',
        author => '<?>',
        copyright => '20?? <?>',
        flags => 0,
        startPage => 0,
        pageLength => 0,
        reserved => 0,
        data => '',
    };

    $self->{PADDING} = '';

    $self->{FILESIZE} = 0x7C;
    $self->{FILENAME} = '';
}

sub read {
    my ($self, $filename) = @_;
    my $hdr;
    my $i;
    my ($size, $totsize);
    my $data;
    my $FH;
    my ($PSID, $version, $dataOffset);
    my @hdr;
    my $hdrlength;

    # Either a scalar filename (or nothing) was passed in, in which case
    # we'll open it, or a filehandle was passed in, in which case we just
    # skip the following step.

    if (ref(\$filename) ne "GLOB") {

        $filename = $self->{FILENAME} if (!(defined $filename));

        if (!$filename) {
            confess("No filename was specified");
            $self->initialize();
            return undef;
        }

        if (!($FH = new FileHandle ("< $filename"))) {
            confess("Error opening $filename");
            $self->initialize();
            return undef;
        }
    }

    # Just to make sure...
    binmode $FH;
    seek($FH,0,0);

    $size = read ($FH, $hdr, 8);

    if (!$size) {
        confess("Error reading $filename");
        $self->initialize();
        return undef;
    }

    $totsize += $size;

    ($PSID, $version, $dataOffset) = unpack ("A4nn", $hdr);

    if ( !(($PSID eq 'PSID') && (($version == 1) or ($version == 2))) ) {
        # Not a valid PSID file recognized by this class.
#        confess("File $filename is not a valid PSID file");
        $self->initialize();
        return undef;
    }

    # Valid PSID file.

    $self->{PSIDdata}{version} = $version;
    $self->{PSIDdata}{dataOffset} = $dataOffset;

    # Slurp up the rest of the header.
    $size = read ($FH, $hdr, $dataOffset-8);

    # If the header is not as big as indicated by the dataOffset,
    # we have a problem.
    if ($size != ($dataOffset-8)) {
        confess("Error reading $filename - incorrect header");
        $self->initialize();
        return undef;
    }

    $totsize += $size;

    $hdrlength = 2*5+4+32*3;
    (@hdr) = unpack ("nnnnnNa32a32a32", substr($hdr,0,$hdrlength));

    if ($version > 1) {
        my @temphdr;
        # PSID v2NG has 4 more fields.
        (@temphdr) = unpack ("nCCn", substr($hdr,$hdrlength,2+1+1+2));
        push (@hdr, @temphdr);
        $hdrlength += 2+1+1+2;
    }
    else {
        # PSID v1 doesn't have these fields.
        $self->{PSIDdata}{flags} = undef;
        $self->{PSIDdata}{startPage} = undef;
        $self->{PSIDdata}{pageLength} = undef;
        $self->{PSIDdata}{reserved} = undef;
    }

    # Store header info.
    for ($i=0; $i <= $#hdr; $i++) {
        $self->{PSIDdata}{$PSIDfieldNames[$i+2]} = $hdr[$i];
    }

    # Put the rest into PADDING. This might put nothing in it!
    $self->{PADDING} = substr($hdr,$hdrlength);

    # Read the C64 data - can't be more than 64KB + 2 bytes load address.
    $size = read ($FH, $data, 65535+2);

    # We allow a 0 length data.
    if (!defined($size)) {
        confess("Error reading $filename");
        $self->initialize();
        return undef;
    }

    $totsize += $size;

    if (ref(\$filename) ne "GLOB") {
        $FH->close();
        $self->{FILENAME} = $filename;
    }

    $self->{PSIDdata}{data} = $data;

    $self->{FILESIZE} = $totsize;

    return 1;
}

sub write {
    my ($self, $filename) = @_;
    my $output;
    my @hdr;
    my $i;
    my $FH;

    # Either a scalar filename (or nothing) was passed in, in which case
    # we'll open it, or a filehandle was passed in, in which case we just
    # skip the following step.

    if (ref(\$filename) ne "GLOB") {
        $filename = $self->{FILENAME} if (!(defined $filename));

        if (!$filename) {
            confess("No filename was specified");
            return undef;
        }

        if (!($FH = new FileHandle ("> $filename"))) {
            confess("Couldn't write $filename");
            return undef;
        }
    }

    # Just to make sure...
    binmode $FH;
    seek($FH,0,0);

    if ($self->{validateWrite}) {
        $self->validate();
    }

    $hdr[0] = "PSID";
    for ($i=0; $i <= 10; $i++) {
        $hdr[$i+1] = $self->{PSIDdata}{$PSIDfieldNames[$i]};
    }

    $output = pack ("A4nnnnnnnNa32a32a32", @hdr);
    print $FH $output;

    # PSID version 2NG has 4 more fields.
    if ($self->{PSIDdata}{version} > 1) {
        $output = pack ("nCCn", ($self->{PSIDdata}{flags}, $self->{PSIDdata}{startPage}, $self->{PSIDdata}{pageLength}, $self->{PSIDdata}{reserved}));
        print $FH $output;
    }

    print $FH $self->{PADDING};

    print $FH $self->{PSIDdata}{data};

    if (ref(\$filename) ne "GLOB") {
        $FH->close();
    }
}

# Notice that if no specific fieldname is given and we are in array/hash
# context, all fields are returned!
sub get {
    my ($self, $fieldname) = @_;
    my %PSIDhash;
    my $field;

    foreach $field (keys %{$self->{PSIDdata}}) {
        $PSIDhash{$field} = $self->{PSIDdata}{$field};
    }

    # Strip off trailing NULLs.
    $PSIDhash{name} =~ s/\x00*$//;
    $PSIDhash{author} =~ s/\x00*$//;
    $PSIDhash{copyright} =~ s/\x00*$//;

    return if (!(defined wantarray()));

    if (!(defined $fieldname)) {
        # No specific fieldname is given. Assume user wants a hash of
        # field values.
        if (wantarray) {
            return %PSIDhash;
        }
        else {
            confess ("Nothing to get, not in array context");
            return undef;
        }
    }

    if (!grep(/^$fieldname$/, @PSIDfieldNames)) {
        confess ("No such fieldname: $fieldname");
        return undef;
    }

    return $PSIDhash{$fieldname};
}

sub getFileName {
    my ($self) = @_;

    return $self->{FILENAME};
}

sub getFileSize {
    my ($self) = @_;

    return $self->{FILESIZE};
}

sub getRealLoadAddress {
    my ($self) = @_;
    my $REAL_LOAD_ADDRESS;

    # It's a read-only "implicit" field, so we just calculate it
    # on the fly.
    if ($self->{PSIDdata}{data} and $self->{PSIDdata}{loadAddress} == 0) {
        $REAL_LOAD_ADDRESS = unpack("v", substr($self->{PSIDdata}{data}, 0, 2));
    }
    else {
        $REAL_LOAD_ADDRESS = $self->{PSIDdata}{loadAddress};
    }

    return $REAL_LOAD_ADDRESS;
}

sub getSpeed($) {
    my ($self, $songnumber) = @_;

    $songnumber = 1 if ((!defined($songnumber)) or ($songnumber < 1));

    if ($songnumber > $self->{PSIDdata}{songs}) {
        confess ("Song number '$songnumber' is invalid!");
        return undef;
    }

    $songnumber = 32 if ($songnumber > 32);

    return (($self->{PSIDdata}{speed} >> ($songnumber-1)) & 0x1);
}

sub getMUSPlayer {
    my ($self) = @_;

    return undef if (!defined($self->{PSIDdata}{flags}));

    return (($self->{PSIDdata}{flags} >> $MUSPLAYER_OFFSET) & 0x1);
}

sub isMUSPlayerRequired {
    my ($self) = @_;

    return $self->getMUSPlayer();
}

sub getPlaySID {
    my ($self) = @_;

    return undef if (!defined($self->{PSIDdata}{flags}));

    return (($self->{PSIDdata}{flags} >> $PLAYSID_OFFSET) & 0x1);
}

sub isPlaySIDSpecific {
    my ($self) = @_;

    return $self->getPlaySID();
}

sub getClock {
    my ($self) = @_;

    return undef if (!defined($self->{PSIDdata}{flags}));

    return (($self->{PSIDdata}{flags} >> $CLOCK_OFFSET) & 0x3);
}

sub getClockByName {
    my ($self) = @_;
    my $clock;

    return undef if (!defined($self->{PSIDdata}{flags}));

    $clock = $self->getClock();

    if ($clock == 0) {
        $clock = 'UNKNOWN';
    }
    elsif ($clock == 1) {
        $clock = 'PAL';
    }
    elsif ($clock == 2) {
        $clock = 'NTSC';
    }
    elsif ($clock == 3) {
        $clock = 'EITHER';
    }

    return $clock;
}

sub getSIDModel {
    my ($self) = @_;

    return undef if (!defined($self->{PSIDdata}{flags}));

    return (($self->{PSIDdata}{flags} >> $SIDMODEL_OFFSET) & 0x3);
}

sub getSIDModelByName {
    my ($self) = @_;
    my $SIDModel;

    return undef if (!defined($self->{PSIDdata}{flags}));

    $SIDModel = $self->getSIDModel();

    if ($SIDModel == 0) {
        $SIDModel = 'UNKNOWN';
    }
    elsif ($SIDModel == 1) {
        $SIDModel = '6581';
    }
    elsif ($SIDModel == 2) {
        $SIDModel = '8580';
    }
    elsif ($SIDModel == 3) {
        $SIDModel = 'EITHER';
    }

    return $SIDModel;
}

# Notice that you have to pass in a hash (field-value pairs)!
sub set(@) {
    my ($self, %PSIDhash) = @_;
    my $fieldname;
    my $paddinglength;
    my $i;
    my $version;
    my $offset;

    foreach $fieldname (keys %PSIDhash) {

        if (!grep(/^$fieldname$/, @PSIDfieldNames)) {
            confess ("No such fieldname: $fieldname");
            next;
        }

        # Do some basic sanity checking.

        if ($fieldname eq 'version' or $fieldname eq 'dataOffset') {
            if ($fieldname eq 'dataOffset') {
                $version = $self->{PSIDdata}{version};
                $offset = $PSIDhash{$fieldname};
            }
            else {
                $version = $PSIDhash{$fieldname};
                $offset = $self->{PSIDdata}{dataOffset};
            }

            if ($version == 1) {
                # PSID v1 values are set in stone.
                $self->{PSIDdata}{version} = 1;
                $self->{PSIDdata}{dataOffset} = 0x76;
                $self->{PSIDdata}{flags} = undef;
                $self->{PSIDdata}{startPage} = undef;
                $self->{PSIDdata}{pageLength} = undef;
                $self->{PSIDdata}{reserved} = undef;
                $self->{PADDING} = '';
                next;
            }
            elsif ($version == 2) {
                # In PSID v2NG we allow dataOffset to be larger than 0x7C.

                if ($offset < 0x7C) {
                    $self->{PSIDdata}{dataOffset} = 0x7C;
                    $self->{PADDING} = '';
                }
                else {
                    $paddinglength = $offset - 0x7C;

                    if (length($self->{PADDING}) < $paddinglength) {
                        # Add as many zeroes as necessary.
                        for ($i=1; $i <= $paddinglength; $i++) {
                            $self->{PADDING} .= pack("C", 0x00);
                        }
                    }
                    else {
                        # Take the relevant portion of the existing padding.
                        $self->{PADDING} = substr($self->{PADDING},0,$paddinglength);
                    }
                }
                $self->{PSIDdata}{flags} = 0 if (!$self->{PSIDdata}{flags});
                $self->{PSIDdata}{reserved} = 0 if (!$self->{PSIDdata}{reserved});
                $self->{PSIDdata}{startPage} = 0 if (!$self->{PSIDdata}{startPage});
                $self->{PSIDdata}{pageLength} = 0 if (!$self->{PSIDdata}{pageLength});
                $self->{PSIDdata}{version} = $version;
                $self->{PSIDdata}{dataOffset} = $offset;
                next;
            }
            else {
                confess ("Invalid PSID version number '$version' - ignored");
                next;
            }
        }

        if (($self->{PSIDdata}{version} < 2) and
            (($fieldname eq 'flags') or ($fieldname eq 'reserved') or
             ($fieldname eq 'startPage') or ($fieldname eq 'pageLength'))) {

            confess ("Can't change '$fieldname' when PSID version is set to 1");
            next;
        }

        $self->{PSIDdata}{$fieldname} = $PSIDhash{$fieldname};
    }

    $self->{FILESIZE} = $self->{PSIDdata}{dataOffset} + length($self->{PADDING}) +
        length($self->{PSIDdata}{data});

    return 1;
}

sub setFileName($) {
    my ($self, $filename) = @_;

    $self->{FILENAME} = $filename;
}

sub setSpeed($$) {
    my ($self, $songnumber, $value) = @_;

    if (!defined($songnumber)) {
        confess ("No song number was specified!");
        return undef;
    }

    if (!defined($value)) {
        confess ("No speed value was specified!");
        return undef;
    }

    if (($songnumber > $self->{PSIDdata}{songs}) or ($songnumber < 1)) {
        confess ("Song number '$songnumber' is invalid!");
        return undef;
    }

    if (($value ne 0) and ($value ne 1)) {
        confess ("Specified value '$value' is invalid!");
        return undef;
    }

    $songnumber = 32 if ($songnumber > 32);
    $songnumber = 1 if ($songnumber < 1);

    # First, clear the bit in question.
    $self->{PSIDdata}{speed} &= ~(0x1 << ($songnumber-1));

    # Then set it.
    $self->{PSIDdata}{speed} |= ($value << ($songnumber-1));
}

sub setMUSPlayer($) {
    my ($self, $MUSplayer) = @_;

    if (!defined($self->{PSIDdata}{flags})) {
        confess ("Cannot set this field when PSID version is 1!");
        return undef;
    }

    if (($MUSplayer ne 0) and ($MUSplayer ne 1)) {
        confess ("Specified value '$MUSplayer' is invalid!");
        return undef;
    }

    # First, clear the bit in question.
    $self->{PSIDdata}{flags} &= ~(0x1 << $MUSPLAYER_OFFSET);

    # Then set it.
    $self->{PSIDdata}{flags} |= ($MUSplayer << $MUSPLAYER_OFFSET);
}

sub setPlaySID($) {
    my ($self, $PlaySID) = @_;

    if (!defined($self->{PSIDdata}{flags})) {
        confess ("Cannot set this field when PSID version is 1!");
        return undef;
    }

    if (($PlaySID ne 0) and ($PlaySID ne 1)) {
        confess ("Specified value '$PlaySID' is invalid!");
        return undef;
    }

    # First, clear the bit in question.
    $self->{PSIDdata}{flags} &= ~(0x1 << $PLAYSID_OFFSET);

    # Then set it.
    $self->{PSIDdata}{flags} |= ($PlaySID << $PLAYSID_OFFSET);
}

sub setClock($) {
    my ($self, $clock) = @_;

    if (!defined($self->{PSIDdata}{flags})) {
        confess ("Cannot set this field when PSID version is 1!");
        return undef;
    }

    if (($clock < 0) or ($clock > 3)) {
        confess ("Specified value '$clock' is invalid!");
        return undef;
    }

    # First, clear the bits in question.
    $self->{PSIDdata}{flags} &= ~(0x3 << $CLOCK_OFFSET);

    # Then set them.
    $self->{PSIDdata}{flags} |= ($clock << $CLOCK_OFFSET);
}

sub setClockByName($) {
    my ($self, $clock) = @_;

    if (!defined($self->{PSIDdata}{flags})) {
        confess ("Cannot set this field when PSID version is 1!");
        return undef;
    }

    if ($clock =~ /^(unknown|none|neither)$/i) {
        $clock = 0;
    }
    elsif ($clock =~ /^PAL$/i) {
        $clock = 1;
    }
    elsif ($clock =~ /^NTSC$/i) {
        $clock = 2;
    }
    elsif ($clock =~ /^(any|both|either)$/i) {
        $clock = 3;
    }
    else {
        confess ("Specified value '$clock' is invalid!");
        return undef;
    }

    $self->setClock($clock);
}

sub setSIDModel($) {
    my ($self, $SIDModel) = @_;

    if (!defined($self->{PSIDdata}{flags})) {
        confess ("Cannot set this field when PSID version is 1!");
        return undef;
    }

    if (($SIDModel < 0) or ($SIDModel > 3)) {
        confess ("Specified value '$SIDModel' is invalid!");
        return undef;
    }

    # First, clear the bits in question.
    $self->{PSIDdata}{flags} &= ~(0x3 << $SIDMODEL_OFFSET);

    # Then set them.
    $self->{PSIDdata}{flags} |= ($SIDModel << $SIDMODEL_OFFSET);
}

sub setSIDModelByName($) {
    my ($self, $SIDModel) = @_;

    if (!defined($self->{PSIDdata}{flags})) {
        confess ("Cannot set this field when PSID version is 1!");
        return undef;
    }

    if ($SIDModel =~ /^(unknown|none|neither)$/i) {
        $SIDModel = 0;
    }
    elsif (($SIDModel =~ /^6581$/) or ($SIDModel == 6581)) {
        $SIDModel = 1;
    }
    elsif (($SIDModel =~ /^8580$/i) or ($SIDModel == 8580)) {
        $SIDModel = 2;
    }
    elsif ($SIDModel =~ /^(any|both|either)$/i) {
        $SIDModel = 3;
    }
    else {
        confess ("Specified value '$SIDModel' is invalid!");
        return undef;
    }

    $self->setSIDModel($SIDModel);
}

sub getFieldNames {
    my ($self) = @_;
    my (@PSIDfields) = @PSIDfieldNames;

    return (@PSIDfields);
}

sub getMD5 {
    my ($self) = @_;

    use Digest::MD5;

    my $md5 = Digest::MD5->new;

    if (($self->{PSIDdata}{loadAddress} == 0) and $self->{PSIDdata}{data}) {
        $md5->add(substr($self->{PSIDdata}{data},2));
    }
    else {
        $md5->add($self->{PSIDdata}{data});
    }

    $md5->add(pack("v", $self->{PSIDdata}{initAddress}));
    $md5->add(pack("v", $self->{PSIDdata}{playAddress}));

    my $songs = $self->{PSIDdata}{songs};
    $md5->add(pack("v", $songs));

    my $speed = $self->{PSIDdata}{speed};

    for (my $i=0; $i < $songs; $i++) {
        my $speedFlag;
        if ( ($speed & (1 << $i)) == 0) {
            $speedFlag = 0;
        }
        else {
            $speedFlag = 60;
        }
        $md5->add(pack("C",$speedFlag));
    }

    return ($md5->hexdigest);
}

sub alwaysValidateWrite($) {
    my ($self, $setting) = @_;

    $self->{validateWrite} = $setting;
}

sub validate {
    my ($self) = @_;
    my $field;
    my $MUSPlayer;
    my $PlaySID;
    my $clock;
    my $SIDModel;

    # Change to version v2.
    if ($self->{PSIDdata}{version} < 2) {
#        carp ("Changing PSID to v2");
        $self->{PSIDdata}{version} = 2;
    }

    if ($self->{PSIDdata}{dataOffset} != 0x7C) {
        $self->{PSIDdata}{dataOffset} = 0x7C;
#        carp ("'dataOffset' was not 0x007C - set to 0x007C");
    }

    # Sanity check the fields.

    # Textual fields can't be longer than 31 chars.
    foreach $field (qw(name author copyright)) {

        # Take off any superfluous null-padding.
        $self->{PSIDdata}{$field} =~ s/\x00*$//;

        if (length($self->{PSIDdata}{$field}) > 31) {
            $self->{PSIDdata}{$field} = substr($self->{PSIDdata}{$field}, 0, 31);
#            carp ("'$field' field was longer than 31 chars - chopped to 31");
        }
    }

    # The preferred way is for initAddress to be explicitly specified.
    if ($self->{PSIDdata}{initAddress} == 0) {

        if ($self->{PSIDdata}{loadAddress} == 0) {
            # Get if from the first 2 bytes of data.
            $self->{PSIDdata}{initAddress} = unpack ("v", substr($self->{PSIDdata}{data}, 0, 2));
        }
        else {
            $self->{PSIDdata}{initAddress} = $self->{PSIDdata}{loadAddress};
        }

#        carp ("'initAddress' was 0 - set to $self->{PSIDdata}{initAddress}");
    }

    # The preferred way is for loadAddress to be 0. The data is prepended by
    # those 2 bytes if it needs to be changed.
    if ($self->{PSIDdata}{loadAddress} != 0) {
        $self->{PSIDdata}{data} = pack("v", $self->{PSIDdata}{loadAddress}) . $self->{PSIDdata}{data};
        $self->{PSIDdata}{loadAddress} = 0;
#        carp ("'loadAddress' was non-zero - set to 0");
    }

    # These fields should better be in the 0x0000-0xFFFF range!
    foreach $field (qw(loadAddress initAddress playAddress)) {
        if (($self->{PSIDdata}{$field} < 0) or ($self->{PSIDdata}{$field} > 0xFFFF)) {
#            confess ("'$field' value of $self->{PSIDdata}{$field} is out of range");
            $self->{PSIDdata}{$field} = 0;
        }
    }

    # These fields should better be in the 0x00-0xFF range!
    foreach $field (qw(startPage pageLength)) {
        if (($self->{PSIDdata}{$field} < 0) or ($self->{PSIDdata}{$field} > 0xFF)) {
#            confess ("'$field' value of $self->{PSIDdata}{$field} is out of range");
            $self->{PSIDdata}{$field} = 0;
        }
    }

    # This field's max is 256.
    if ($self->{PSIDdata}{songs} > 256) {
        $self->{PSIDdata}{songs} = 256;
#        carp ("'songs' was more than 256 - set to 256");
    }

    # This field's min is 1.
    if ($self->{PSIDdata}{songs} < 1) {
        $self->{PSIDdata}{songs} = 1;
#        carp ("'songs' was less than 1 - set to 1");
    }

    # If an invalid startSong is specified, set it to 1.
    if ($self->{PSIDdata}{startSong} > $self->{PSIDdata}{songs}) {
        $self->{PSIDdata}{startSong} = 1;
#        carp ("Invalid 'startSong' field - set to 1");
    }

    # Only the relevant fields in 'speed' will be set.
    my $tempSpeed = 0;
    my $maxSongs = $self->{PSIDdata}{songs};

    # There are only 32 bits in speed.
    if ($maxSongs > 32) {
        $maxSongs = 32;
    }

    for (my $i=0; $i < $maxSongs; $i++) {
        $tempSpeed += ($self->{PSIDdata}{speed} & (1 << $i));
    }
    $self->{PSIDdata}{speed} = $tempSpeed;

    # Only the relevant fields in 'flags' will be set.
    $MUSPlayer = $self->isMUSPlayerRequired();
    $PlaySID = $self->isPlaySIDSpecific();
    $clock = $self->getClock();
    $SIDModel = $self->getSIDModel();

    $self->{PSIDdata}{flags} = 0;

    $self->setMUSPlayer($MUSPlayer);
    $self->setPlaySID($PlaySID);
    $self->setClock($clock);
    $self->setSIDModel($SIDModel);

    if ($self->{PSIDdata}{startPage} == 0) {
        $self->{PSIDdata}{pageLength} = 0;
    }

    $self->{PSIDdata}{reserved} = 0;

    # The preferred way is to have no padding between the v2 header and the
    # C64 data.
    if ($self->{PADDING}) {
        $self->{PADDING} = '';
#        carp ("Invalid bytes were between the header and the data - removed them");
    }

    # Recalculate size.
    $self->{FILESIZE} = $self->{PSIDdata}{dataOffset} + length($self->{PADDING}) +
        length($self->{PSIDdata}{data});
}

1;

__END__

=pod

=head1 NAME

Audio::PSID - Perl module to handle PlaySID files (Commodore-64 music files), commonly known as SID files.

=head1 SYNOPSIS

    use Audio::PSID;

    $myPSID = new Audio::PSID ("Test.sid") or die "Whoops!";

    print "Name = " . $myPSID->get('name') . "\n";

    print "MD5 = " . $myPSID->getMD5();

    $myPSID->set(author => 'LaLa',
                 name => 'Test2',
                 copyright => '2001 Hungarian Music Crew');

    $myPSID->validate();
    $myPSID->write("Test2.sid") or die "Couldn't write file!";

    @array = $myPSID->getFieldNames();
    print "Fieldnames = " . join(' ', @array) . "\n";

=head1 DESCRIPTION

This module is designed to handle PlaySID files (usually bearing a .sid
extension), which are music player and data routines converted from the
Commodore-64 computer with an additional informational header prepended. For
further details about the exact file format, see description of all PSID
fields in the PSID_v2NG.txt file included in the module package. For
information about SID tunes in general, see the excellent SIDPLAY homepage at:

B<http://www.geocities.com/SiliconValley/Lakes/5147/>

For PSID v2NG documentation:

B<http://sidplay2.sourceforge.net>

You can find literally thousands of SID tunes in the High Voltage SID
Collection at:

B<http://www.hvsc.c64.org>

This module can handle both version 1 and version 2/2NG PSID files. (Version 2
files are simply v2NG files where v2NG specific fields are set 0.) The module
was designed primarily to make it easier to look at and change the PSID header
fields, so many of the member function are geared towards that. Use
$OBJECT->I<getFieldNames>() to find out the exact names of the fields
currently recognized by this module. Please note that B<fieldnames are
case-sensitive>!

=head2 Member functions

=over 4

=item B<PACKAGE>->B<new>([SCALAR]) or B<PACKAGE>->B<new>([FILEHANDLE])

Returns a newly created PSID object. If neither SCALAR nor FILEHANDLE is
specified, the object is initialized with default values. See
$OBJECT->I<initalize>() below.

If SCALAR or FILEHANDLE is specified, an attempt is made to open the given
file as specified in $OBJECT->I<read>() below.

=item B<OBJECT>->B<initialize>()

Initializes the object with default PSID data as follows:

    version => 2,
    dataOffset => 0x7C,
    name => '<?>',
    author => '<?>',
    copyright => '20?? <?>',
    data => '',

Every other PSID field (I<loadAddress>, I<initAddress>, I<playAddress>,
I<songs>, I<startSong>, I<speed>, I<flags>, I<startPage>, I<pageLength> and
I<reserved>) is set to 0. I<FILENAME> is set to '' and the filesize is set to
0x7C.

=item B<$OBJECT>->B<read>([SCALAR]) or B<$OBJECT>->B<read>([FILEHANDLE])

Reads the PSID file given by the filename SCALAR or by FILEHANDLE and
populates the fields with the values taken from this file. If the given file
is a PSID version 1 file, the fields of I<flags>, I<startPage>, I<pageLength>
and I<reserved> are set to undef.

If neither SCALAR nor FILEHANDLE is specified, the value of I<FILENAME> is
used to determine the name of the input file. If that is not set, either, the
module is initialized with default data and returns an undef. Note that SCALAR
and FILEHANDLE here can be different than the value of I<FILENAME>! If SCALAR
is defined, it will overwrite the filename stored in I<FILENAME>, otherwise it
is not modified. So, watch out when passing in a FILEHANDLE, because
I<FILENAME> will not be modified!

If the file turns out to be an invalid PSID file, the module is initialized
with default data and returns an undef. Valid PSID files must have the ASCII
string 'PSID' as their first 4 bytes, and either 0x0001 or 0x0002 as the next
2 bytes in big-endian format.

=item B<$OBJECT>->B<write>([SCALAR]) or B<$OBJECT>->B<write>([FILEHANDLE])

Writes the PSID file given by the filename SCALAR or by FILEHANDLE to disk. If
neither SCALAR nor FILEHANDLE is specified, the value of I<FILENAME> is used
to determine the name of the output file. If that is not set, either, returns
an undef. Note that SCALAR and FILEHANDLE here can be different than the value
of I<FILENAME>! If SCALAR is defined, it will not overwrite the filename
stored in I<FILENAME>.

I<write> will create a version 1 or version 2/2NG PSID file depending on the
value of the I<version> field, regardless of whether the other fields are set
correctly or not, or even whether they are undef'd or not. However, if
$OBJECT->I<alwaysValidateWrite>(1) was called beforehand, I<write> will always
write a validated v2NG PSID file. See below.

=item B<$OBJECT>->B<get>([SCALAR])

Retrieves the value of the PSID field given by the name SCALAR, or returns a
hash of all the recognized PSID fields with their values if called in an
array/hash context.

If the fieldname given by SCALAR is unrecognized, the operation is ignored
and an undef is returned. If SCALAR is not specified and I<get> is not called
from an array context, the same terrible thing will happen. So try not to do
either of these.

=item B<$OBJECT>->B<getFileName>()

Returns the current I<FILENAME> stored in the object.

=item B<$OBJECT>->B<getFileSize>()

Returns the total size of the PSID file that would be written by
$OBJECT->I<write>() if it was called right now. This means that if you read in
a version 1 file and changed the I<version> field to 2 without actually saving
the file, the size returned here will reflect the size of how big the version
2 file would be.

=item B<$OBJECT>->B<getRealLoadAddress>()

The "real load address" indicates what is the actual Commodore-64 memory
location where the PSID data is going to be loaded into. If I<loadAddress> is
non-zero, then I<loadAddress> is returned here, otherwise it's the first two
bytes of I<data> (read from there in little-endian format).

=item B<$OBJECT>->B<getSpeed>([SCALAR])

Returns the speed of the song number specified by SCALAR. If no SCALAR is
specified, returns the speed of song #1. Speed can be either 0 (indicating a
vertical blank interrupt (50Hz PAL, 60Hz NTSC)), or 1 (indicating CIA 1 timer
interrupt (default is 60Hz)).

=item B<$OBJECT>->B<getMUSPlayer>()

Returns the value of the 'MUSPlayer' bit of the I<flags> field if I<flags> is
specified (i.e. when I<version> is 2), or undef otherwise. The returned value
is either 0 (indicating a built-in music player) or 1 (indicating that I<data>
is a Compute!'s Sidplayer MUS data and the music player must be merged).

=item B<$OBJECT>->B<isMUSPlayerRequired>()

This is an alias for $OBJECT->I<getMUSPlayer>().

=item B<$OBJECT>->B<getPlaySID>()

Returns the value of the 'psidSpecific' bit of the I<flags> field if I<flags>
is specified (i.e. when I<version> is 2), or undef otherwise. The returned
value is either 0 (indicating that I<data> is Commodore-64 compatible) or
1 (indicating that I<data> is PlaySID specific).

=item B<$OBJECT>->B<isPlaySIDSpecific>()

This is an alias for $OBJECT->I<getPlaySID>().

=item B<$OBJECT>->B<getClock>()

Returns the value of the 'clock' (video standard) bits of the I<flags> field
if I<flags> is specified (i.e. when I<version> is 2), or undef otherwise. The
returned value is one of 0 (UNKNOWN), 1 (PAL), 2 (NTSC) or 3 (EITHER).

=item B<$OBJECT>->B<getClockByName>()

Returns the textual value of the 'clock' (video standard) bits of the I<flags>
field if I<flags> is specified (i.e. when I<version> is 2), or undef
otherwise. The textual value will be one of UNKNOWN, PAL, NTSC or EITHER.

=item B<$OBJECT>->B<getSIDModel>()

Returns the value of the 'sidModel' bits of the I<flags> field if I<flags> is
specified (i.e. when I<version> is 2), or undef otherwise. The returned value
is one of 0 (UNKNOWN), 1 (6581), 2 (8580) or 3 (EITHER).

=item B<$OBJECT>->B<getSIDModelByName>()

Returns the textual value of the 'sidModel' bits of the I<flags> field if
I<flags> is specified (i.e. when I<version> is 2), or undef otherwise. The
textual value will be one of UNKNOWN, 6581, 8580 or EITHER.

=item B<$OBJECT>->B<set>(field => value [, field => value, ...] )

Given one or more field-value pairs it changes the PSID fields given by
I<field> to have I<value>.

If you try to set a field that is unrecognized, that particular field-value
pair will be ignored. Trying to set the I<version> field to anything other
than 1 or 2 will result in criminal prosecution, expulsion, and possibly
death... Actually, it won't harm you, but the invalid value will be ignored.

Whenever the version number is changed to 1, the I<flags>, I<startPage>,
I<pageLength> and I<reserved> fields are automatically set to be undef'd, and
the I<dataOffset> field is reset to 0x0076. Whenever the version number is
changed to 2, the I<flags>, I<startPage>, I<pageLength> and I<reserved> fields
are zeroed out.

If you try to set I<flags>, I<startPage>, I<pageLength> or I<reserved> when
I<version> is not 2, the values will be ignored. Trying to set I<dataOffset>
when I<version> is 1 will always reset its value to 0x0076, and I<dataOffset>
can't be set to lower than 0x007C if I<version> is 2. You can set it higher,
though, in which case either the relevant portion of the original extra
padding bytes between the PSID header and the I<data> will be preserved, or
additional 0x00 bytes will be added between the PSID header and the I<data> if
necessary.

=item B<$OBJECT>->B<setFileName>([SCALAR])

Sets the I<FILENAME> to SCALAR. This filename is used by $OBJECT->I<read>()
and $OBJECT->I<write>() when either one of them is called without any
arguments. SCALAR can specify either a relative or an absolute pathname to the
file - in fact, it can be anything that can be passed to a B<FileHandle>
type object as a filename.

=item B<$OBJECT>->B<setSpeed>([SCALAR1], [SCALAR2])

Changes the speed of the song number specified by SCALAR1 to that of SCALAR2.
SCALAR1 has to be more than 1 and less than the value of the I<songs> field.
SCALAR2 can be either 0 (indicating a vertical blank interrupt (50Hz PAL, 60Hz
NTSC)), or 1 (indicating CIA 1 timer interrupt (default is 60Hz)). An undef is
returned if neither was specified.

=item B<$OBJECT>->B<setMUSPlayer>([SCALAR])

Changes the value of the 'MUSPlayer' bit of the I<flags> field to SCALAR if
I<flags> is specified (i.e. when I<version> is 2), returns an undef otherwise.
SCALAR must be either 0 (indicating a built-in music player) or 1 (indicating
that I<data> is a Compute!'s Sidplayer MUS data and the music player must be
merged).

=item B<$OBJECT>->B<setPlaySID>([SCALAR])

Changes the value of the 'psidSpecific' bit of the I<flags> field to SCALAR if
I<flags> is specified (i.e. when I<version> is 2), returns an undef otherwise.
SCALAR must be either 0 (indicating that I<data> is Commodore-64 compatible)
or 1 (indicating that I<data> is PlaySID specific).

=item B<$OBJECT>->B<setClock>([SCALAR])

Changes the value of the 'clock' (video standard) bits of the I<flags> field
to SCALAR if I<flags> is specified (i.e. when I<version> is 2), returns an
undef otherwise. SCALAR must be one of 0 (UNKNOWN), 1 (PAL), 2 (NTSC) or 3
(EITHER).

=item B<$OBJECT>->B<setClockByName>([SCALAR])

Changes the value of the 'clock' (video standard) bits of the I<flags> field
if I<flags> is specified (i.e. when I<version> is 2), returns an undef
otherwise. SCALAR must be be one of UNKNOWN, NONE, NEITHER (all 3 indicating
UNKNOWN), PAL, NTSC or ANY, BOTH, EITHER (all 3 indicating EITHER) and is
case-insensitive.

=item B<$OBJECT>->B<setSIDModel>([SCALAR])

Changes the value of the 'sidModel' bits of the I<flags> field if I<flags> is
specified (i.e. when I<version> is 2), returns an undef otherwise. SCALAR must
be one of 0 (UNKNOWN), 1 (6581), 2 (8580) or 3 (EITHER).

=item B<$OBJECT>->B<setSIDModelByName>([SCALAR])

Changes the value of the 'sidModel' bits of the I<flags> field if I<flags> is
specified (i.e. when I<version> is 2), returns an undef otherwise. SCALAR must
be be one of UNKNOWN, NONE, NEITHER (all 3 indicating UNKNOWN), 6581, 8580 or
ANY, BOTH, EITHER (all 3 indicating EITHER) and is case-insensitive.

=item B<$OBJECT>->B<getFieldNames>()

Returns an array that contains the PSID fieldnames recognized by this module,
regardless of the PSID version number. All fieldnames are taken from the
standard PSID v2NG file format specification, but do B<not> include those
fields that are themselves contained in another field, namely any field that
is inside the I<flags> field. The fieldname I<FILENAME> is also B<not>
returned here, since that is considered to be a descriptive parameter of the
PSID file and is not part of the PSID v2NG specification.

=item B<$OBJECT>->B<getMD5>()

Returns a string containing a hexadecimal representation of the 128-bit MD5
fingerprint calculated from the following PSID fields: I<data> (excluding the
first 2 bytes if I<loadAddress> is 0), I<initAddress>, I<playAddress>,
I<songs>, and the relevant bits of I<speed>. The MD5 fingerprint calculated
this way is used, for example, to index into the songlength database, because
it provides a way to uniquely identify SID tunes even if the textual credit
fields of the PSID file were changed.

=item B<$OBJECT>->B<alwaysValidateWrite>([SCALAR])

If SCALAR is non-zero, $OBJECT->I<validate>() will always be called before
$OBJECT->I<write>() actually writes a file to disk. If SCALAR is 0, this won't
happen and the stored PSID data will be written to disk virtually untouched -
this is also the default behavior.

=item B<$OBJECT>->B<validate>()

Regardless of how the PSID fields were populated, this operation will update
the stored PSID data to comply with the latest PSID version (v2NG). Thus, it
changes the PSID I<version> to 2, and it will also change the other fields so
that they take on their prefered values. Operations done by this member
function include (but are not limited to):

=over 4

=item *

bumping up the PSID version to v2NG by setting I<version> to 2,

=item *

setting the I<dataOffset> to 0x007C,

=item *

chopping the textual fields of I<name>, I<author> and I<copyright> to their
maximum length of 31 characters,

=item *

changing the I<initAddress> to a valid non-zero value,

=item *

changing the I<loadAddress> to 0 if it is non-zero (and also prepending the
I<data> with the non-zero I<loadAddress>)

=item *

making sure that I<loadAddress>, I<initAddress> and I<playAddress> are within
the 0x0000-0xFFFF range (since the Commodore-64 had only 64KB addressable
memory), and setting them to 0 if they aren't,

=item *

making sure that I<startPage> and I<pageLength> are within the 0x00-0xFF
range, and setting them to 0 if they aren't,

=item *

setting the I<pageLength> to 0 if I<startPage> is 0.

=item *

making sure that I<songs> is within the range of [1,256], and changing it to
1 if it less than that or to 256 if it is more than that,

=item *

making sure that I<startSong> is within the range of [1,I<songs>], and changing
it to 1 if it is not,

=item *

setting only the relevant bits in I<speed>, regardless of how many bits were
set before, and setting the rest to 0,

=item *

setting only the recognized bits in I<flags>, namely 'MUSPlayer',
'psidSpecific', 'clock' and 'sidModel' (bits 0-5), and setting the rest to 0,

=item *

removing extra bytes that may have been between the PSID header and I<data>
in the file (usually happens when I<dataOffset> is larger than the total size
of the PSID header, i.e. larger than 0x007C),

=item *

setting the I<reserved> field to 0,

=back

=back

=head1 BUGS

None is known to exist at this time. If you find any bugs in this module,
report them to the author (see L<"COPYRIGHT"> below).

=head1 TO DO LIST

More or less in order of perceived priority, from most urgent to least urgent.

=over 4

=item *

Extend the module to be able to handle all kinds of C64 music files (eg. MUS,
.INFO, old .SID and .DAT, etc.), not just PSID .SIDs.

=item *

Overload '=' so two objects can be assigned to each other?

=back

=head1 COPYRIGHT

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

PSID Perl module - (C) 1999-2002 LaLa <LaLa@C64.org> (Thanks to Adam Lorentzon
for showing me how to extract binary data from PSID files! :-)

PSID MD5 calculation - (C) 2001 Michael Schwendt <sidplay@geocities.com>

=head1 VERSION

Version v2.00, released to CPAN on February 20, 2002.

First version created on June 11, 1999.

=head1 SEE ALSO

the SIDPLAY homepage for the PSID file format documentation:

B<http://www.geocities.com/SiliconValley/Lakes/5147/>

the SIDPLAY2 homepage for documents about the PSID v2NG extensions:

B<http://sidplay2.sourceforge.net>

the High Voltage SID Collection, the most comprehensive archive of SID tunes
for SID files:

B<http://www.hvsc.c64.org>

L<Digest::MD5>

=cut
