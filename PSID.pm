package Audio::PSID;

require 5;

use Carp;
use strict;
use vars qw($VERSION);
use FileHandle;

$VERSION = "1.60";

# These are the recognized field names for a PSID file. They must appear in
# the order they appear in the PSID file after the first 4 ASCII bytes "PSID".
my (@PSIDfieldNames) = qw(version dataOffset loadAddress initAddress
                          playAddress songs startSong speed name author
                          copyright flags reserved data);

# Additional data stored in the class that are not part of the PSID file
# format are: FILESIZE, FILENAME, and the implicit REAL_LOAD_ADDRESS.
#
# PADDING is used to hold any extra bytes that may be between the standard
# PSID header and the data (usually happens when dataOffset is more than
# 0x007C).

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
        dataOffset => 0x7c,
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
        reserved => 0,
        data => '',
    };

    $self->{PADDING} = '';

    $self->{FILESIZE} = 0x7c;
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

    if ($version == 2) {
        my @temphdr;
        # PSID v2 has two more fields.
        (@temphdr) = unpack ("nN", substr($hdr,$hdrlength,2+4));
        push (@hdr, @temphdr);
        $hdrlength += 2+4;
    }
    else {
        # PSID v1 doesn't have these fields.
        $self->{PSIDdata}{flags} = undef;
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
    }

    $self->{PSIDdata}{data} = $data;

    $self->{FILESIZE} = $totsize;
    $self->{FILENAME} = $filename;

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
        $filename = $self->{PSIDdata}{FILENAME} if (!(defined $filename));

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

    # PSID version 2 has two more fields.
    if ($self->{PSIDdata}{version} == 2) {
        $output = pack ("nN", ($self->{PSIDdata}{flags}, $self->{PSIDdata}{reserved}));
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
    $PSIDhash{FILESIZE} = $self->{FILESIZE};
    $PSIDhash{FILENAME} = $self->{FILENAME};

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

    # These special fields are handled separate from actual PSID data.
    if ($fieldname eq "FILENAME") {
        return $PSIDhash{FILENAME};
    }

    if ($fieldname eq "FILESIZE") {
        return $PSIDhash{FILESIZE};
    }

    if ($fieldname eq "REAL_LOAD_ADDRESS") {
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

    if (!grep(/^$fieldname$/, @PSIDfieldNames)) {
        confess ("No such fieldname: $fieldname");
        return undef;
    }

    return $PSIDhash{$fieldname};
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

        # This is a special field handled separate from actual PSID data.
        if ($fieldname eq "FILENAME") {
            $self->{FILENAME} = $PSIDhash{$fieldname};
            next;
        }

        # These are the fields that should not be modified by the user.
        if ($fieldname eq "FILESIZE") {
            confess ("Read-only field: $fieldname");
            next;
        }

        if ($fieldname eq 'REAL_LOAD_ADDRESS') {
            confess ("Read-only field: $fieldname");
            next;
        }

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
                $self->{PSIDdata}{reserved} = undef;
                $self->{PADDING} = '';
                next;
            }
            elsif ($version == 2) {
                # In PSID v2 we allow dataOffset to be larger than 0x7C.

                if ($offset < 0x7c) {
                    $self->{PSIDdata}{dataOffset} = 0x7c;
                    $self->{PADDING} = '';
                }
                else {
                    $paddinglength = $offset - 0x7c;

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
                $self->{PSIDdata}{version} = $version;
                $self->{PSIDdata}{dataOffset} = $offset;
                next;
            }
            else {
                confess ("PSID version number $version is greater than 2 - ignored");
                next;
            }
        }

        if (($self->{PSIDdata}{version} != 2) and
            (($fieldname eq 'flags') or ($fieldname eq 'reserved'))) {

            confess ("Can't change '$fieldname' when PSID version is set to 1");
            next;
        }

        $self->{PSIDdata}{$fieldname} = $PSIDhash{$fieldname};
    }

    $self->{FILESIZE} = $self->{PSIDdata}{dataOffset} + length($self->{PADDING}) +
        length($self->{PSIDdata}{data});

    return 1;
}

sub getFieldNames() {
    my ($self) = @_;
    my (@PSIDfields) = @PSIDfieldNames;

    push (@PSIDfields, "FILENAME");
    push (@PSIDfields, "FILESIZE");
    push (@PSIDfields, "REAL_LOAD_ADDRESS");

    return (@PSIDfields);
}

sub getMD5() {
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

sub validate() {
    my ($self) = @_;
    my $field;

    # Change to version v2.
    if ($self->{PSIDdata}{version} != 2) {
#        carp ("Changing PSID to v2");
        $self->{PSIDdata}{version} = 2;
    }

    if ($self->{PSIDdata}{dataOffset} != 0x7c) {
        $self->{PSIDdata}{dataOffset} = 0x7c;
#        carp ("'dataOffset' was not 0x007C - set to 0x007C");
    }

    $self->{PSIDdata}{flags} = 0 if (!$self->{PSIDdata}{flags});
    $self->{PSIDdata}{reserved} = 0;

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

    # Only the relevant fields in speed will be set.
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

Audio::PSID - Perl class to handle PlaySID files (Commodore-64 music files), commonly known as SID files.

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

This class is designed to handle PlaySID files (usually bearing a .SID
extension), which are music player and data routines converted from the
Commodore-64 computer with an additional informational header prepended. For
further details about the exact file format, the description of all PSID
fields and for about SID tunes in general, see the excellent SIDPLAY homepage
at: B<http://www.geocities.com/SiliconValley/Lakes/5147/> (You can find
literally thousands of SID tunes in the High Voltage SID Collection at:
B<http://www.hvsc.c64.org>)

This class can handle both version 1 and version 2 PSID files. The class was
designed primarily to make it easier to look at and change the PSID header
fields, so many of the methods are geared towards that. Use the
I<getFieldNames> method to find out the exact names of the fields currently
recognized by this class. Please note that B<fieldnames are case-sensitive>!

=head2 Methods

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
    dataOffset => 0x7c,
    name => '<?>',
    author => '<?>',
    copyright => '20?? <?>',
    data => '',

I<FILENAME> is set to '' and I<FILESIZE> is set to 0x7c. All other fields
(I<loadAddress>, I<initAddress>, I<playAddress>, I<songs>, I<startSong>,
I<speed>, I<flags> and I<reserved>) are set to 0. I<REAL_LOAD_ADDRESS> is a
read-only field that is always calculated on-the-fly when its value is
requested, so it's not stored in the object data per se.

=item B<$OBJECT>->B<read>([SCALAR]) or B<$OBJECT>->B<read>([FILEHANDLE])

Reads the PSID file given by the filename SCALAR or by FILEHANDLE and
populates the stored fields with the values taken from this file. If the given
file is a PSID version 1 file, the fields of I<flags> and I<reserved> are set
to be undef.

If neither SCALAR nor FILEHANDLE is specified, the value of the I<FILENAME>
field is used to determine the name of the input file.

If the file turns out to be an invalid PSID file, the class is initialized
with default data only. Valid PSID files must have the ASCII string 'PSID' as
their first 4 bytes, and either 0x0001 or 0x0002 as the next 2 bytes in
big-endian format.

=item B<$OBJECT>->B<write>([SCALAR]) or B<$OBJECT>->B<write>([FILEHANDLE])

Writes the PSID file given by the filename SCALAR or by FILEHANDLE to disk. If
neither SCALAR nor FILEHANDLE is specified, the value of the I<FILENAME> field
is used to determine the name of the output file. Note that SCALAR and
FILEHANDLE here can be different than the value of the I<FILENAME> field! If
SCALAR or FILEHANDLE is defined, it will not overwrite the filename stored in
the I<FILENAME> field.

I<write> will create a version 1 or version 2 PSID file depending on the value
of the I<version> field, regardless of whether the other fields are set
correctly or not, or even whether they are undef'd or not. However, if
$OBJECT->I<alwaysValidateWrite>(1) was called beforehand, I<write> will always
write a valid version 2 PSID file. See below.

=item B<$OBJECT>->B<get>([SCALAR])

Retrieves the value of the field given by the name SCALAR, or returns an
array (actually a hash) of all the recognized PSID fields with their values
if called in an array/hash context.

If the field name given by SCALAR is unrecognized, the operation is ignored
and an undef is returned. If SCALAR is not specified and I<get> is not called
from an array context, the same terrible thing will happen. So try not to do
either of these.

B<NOTE:> I<FILENAME>, I<FILESIZE> and I<REAL_LOAD_ADDRESS> are special fields
that are not really part of a PSID file. I<FILENAME> is simply the name of the
file read in (if changed, the $OBJECT->I<write>() will write all data out to
the new filename). I<FILESIZE> is the the total size of all data that would be
written by $OBJECT->I<write>() if it was called right now (i.e. if you read in
a version 1 file and change it in-memory to version 2, I<FILESIZE> will
reflect the size of how big the version 2 file would be). Finally,
I<REAL_LOAD_ADDRESS> indicates what is the actual Commodore-64 memory location
where the PSID data is going to be loaded into. If I<loadAddress> is non-zero,
then I<REAL_LOAD_ADDRESS> = I<loadAddress>, otherwise it's the first two bytes
of I<data> (read from there in little-endian format).

=item B<$OBJECT>->B<set>(field => value [, field => value, ...] )

Given one or more field-value pairs it sets the PSID fields given by I<field>
to have I<value>. The read-only fields that cannot be set under any
circumstance are I<FILESIZE> and I<REAL_LOAD_ADDRESS>, as these
fields are set automatically or are implicit.

If you try to set a field that is unrecognized, that particular field-value
pair will be ignored. The same happens if you try to change one of the above
read-only fields. Trying to set the I<version> field to anything else than 1
or 2 will result in criminal prosecution, expulsion, and possibly death...
Actually, it won't harm you, but the invalid value will be ignored.

Whenever the version number is set to 1, the I<flags> and I<reserved> fields
are automatically set to be undef'd, and the I<dataOffset> field is reset to
0x0076. If you try to set I<flags> or I<reserved> when I<version> is not 2,
the values will be ignored. Trying to set I<dataOffset> when I<version> is 1
will always be reset its value to 0x0076, and I<dataOffset> can't be set to
lower than 0x007C if I<version> is 2. You can set it higher, though, in which
case either the relevant portion of the original extra padding bytes between
the PSID header and the I<data> will be preserved, or additional 0x00 bytes
will be added between the PSID header and the I<data> if necessary.

The I<FILESIZE> field is always recalculated, so you don't have to worry about
that, even if you change I<dataOffset> or the I<data> portion.

=item B<$OBJECT>->B<getFieldNames>()

Returns an array that contains all the fieldnames recognized by this class,
regardless of the PSID version number. All fieldnames are taken from the
standard PSID file format, except I<FILESIZE>, I<FILENAME> and
I<REAL_LOAD_ADDRESS>, which are not actually part of the PSID header, but
are considered to be descriptive of any PSID file, and are provided merely for
convenience.

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
the stored PSID data to comply with the latest PSID version (currently v2). It
also changes the PSID version to v2 if it is not already that, and it will also
change the fields so that they take on their prefered values. Operations done
by this method include (but are not limited to):

=over 4

=item *

bumping up the PSID version to v2,

=item *

setting the I<dataOffset> to 0x007C,

=item *

setting the I<reserved> field to 0,

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

making sure that I<songs> is within the range of [1,256], and changing it to
1 if it less than that or to 256 if it is more than that,

=item *

making sure that I<startSong> is within the range of [1,I<songs>], and changing
it to 1 if it is not,

=item *

setting only the relevant bits in I<speed>, regardless of how many bits were
set before,

=item *

removing extra bytes that may have been between the PSID header and I<data>
in the file (usually happens when I<dataOffset> is larger than the total size
of the PSID header, i.e. larger than 0x007C),

=item *

recalculating the I<FILESIZE> field.

=back

=back

=head1 BUGS

None is known to exist at this time. If you find any bugs in this module,
report them to the author (see L<"COPYRIGHT"> below).

=head1 TO DO LIST

More or less in order of perceived priority, from most urgent to least urgent.

=over 4

=item *

Maybe those fields not part of the PSID header should have their own getField()
functions?

=item *

Need to think of a good way to extend the class so it can handle the songlength
database and STIL info, too.

=item *

Extend the class to be able to handle all kinds of C64 music files (eg. MUS,
.INFO, old .SID and .DAT, etc.), not just PSID .SIDs.

=item *

Add support for PSID v2B (aka v2NG) redefined fields (proposal is still in
a state of flux):

- I<flags>:

Bit 0 - specifies format of the binary data (0 = built-in music player,
1 = Compute!'s Sidplayer MUS data, music player must be merged).

Bit 1 - specifies video standard (0 = PAL, 1 = NTSC).

Bits 2-3 - specify the SID version (00 = unknonw, 01 = MOS6581, 10 = MOS8580).

Bit 4 - specifies use of PlaySID samples (0 = no PlaySID samples,
1 = PlaySID samples).

Bits 5-15 are reserved and should be set to 0.

- I<speed> is redefined as:

I<speed> is a 32 bit big endian number, starting at offset 0x12. Each bit in
I<speed> specifies the speed for the corresponding tune number, i.e. bit 0
specifies the speed for tune 1. If there are more than 32 tunes, the speed
specified for tune 32 is also used for all higher numbered tunes.

A 0 bit specifies vertical blank interrupt (50Hz PAL, 60Hz NTSC), and a 1 bit
specifies CIA 1 timer interrupt default 60Hz).

Surplus bits in I<speed> should be set to 0.

Note that if I<playAddress> = 0, the bits in I<speed> should still be set for
backwards compatibility with older SID players. New SID players running in a
C64 environment will ignore the speed bits in this case.

- I<reserved> is broken up and is redefined as follows:

I<startpage> is an 8 bit number, starting at offset 0x78.

I<pagelength> is an 8 bit number, starting at offset 0x79. If I<startpage> = 0,
I<pagelength> should be set to 0, too.

I<reserved> is a 16 bit big endian number, starting at offset 0x7a. It is
reserved and should be set to 0.

=item *

Add a get() method to retrieve individual bits from I<speed>? (Input might be
the song number.)

=item *

Overload '=' so two objects can be assigned to each other?

=back

=head1 COPYRIGHT

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

PSID Perl module - (C) 1999-2001 LaLa <LaLa@C64.org> (Thanks to Adam Lorentzon
for showing me how to extract binary data from PSID files! :-)

PSID MD5 calculation - (C) 2001 Michael Schwendt <sidplay@geocities.com>

=head1 VERSION

Version v1.60, released to CPAN on January 6, 2002.

First version created on June 11, 1999.

=head1 SEE ALSO

the SIDPLAY homepage for the PSID file format documentation:
B<http://www.geocities.com/SiliconValley/Lakes/5147/>

the SIDPLAY2 homepage for documents about the PSID v2NG extensions:
B<http://sidplay2.sourceforge.net/>

the High Voltage SID Collection, the most comprehensive archive of SID tunes
for SID files:
B<http://www.hvsc.c64.org>

L<Digest::MD5>

=cut
