use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Data::RadixTree::Shared;

# A creator killed between ftruncate() and header init leaves a full-size,
# all-zero (magic==0) file.  new() must recover it instead of bricking the path,
# but must never clobber a valid or foreign file.

my $dir = tempdir(CLEANUP => 1);
my $p   = "$dir/recover.rdx";

# Learn the on-disk size for this geometry.
{ my $t = Data::RadixTree::Shared->new($p, 4096, 65536); }
my $total = -s $p;
unlink $p;

# 1. Recovery: an abandoned all-zero file of exactly $total bytes is re-initialized.
{
    open my $f, '>', $p or die $!; truncate $f, $total or die $!; close $f;
    is(-s $p, $total, "abandoned file is $total bytes (a killed creator's ftruncate)");
    my $t = eval { Data::RadixTree::Shared->new($p, 4096, 65536) };
    ok($t, "new() recovers an abandoned mid-init file instead of bricking") or diag $@;
  SKIP: {
        skip "no handle", 3 unless $t;
        is($t->count, 0, "recovered tree starts empty (count 0)");
        is($t->insert("key", 42), 1, "recovered tree accepts insert (returns 1, new)");
        is($t->lookup("key"), 42, "recovered tree reads back what it stored");
    }
    undef $t; unlink $p;
}

# 2. No clobber: a file with nonzero (foreign) magic still errors.
{
    open my $f, '>', $p or die $!; print $f "XXXX"; truncate $f, $total or die $!; close $f;
    my $t = eval { Data::RadixTree::Shared->new($p, 4096, 65536) };
    ok(!$t, "new() refuses a foreign nonzero-magic file (no clobber)");
    like($@, qr/invalid/i, "  ... reporting an invalid file");
    undef $t; unlink $p;
}

# 3. No recovery for the wrong size: magic==0 but size != total still errors.
{
    open my $f, '>', $p or die $!; truncate $f, $total + 8 or die $!; close $f;
    my $t = eval { Data::RadixTree::Shared->new($p, 4096, 65536) };
    ok(!$t, "new() refuses an uninitialized file of the wrong size");
    undef $t; unlink $p;
}

# 4. A valid file is attached, never re-initialized (its data survives).
{
    my $a = Data::RadixTree::Shared->new($p, 4096, 65536); $a->insert("keep", 99); undef $a;
    my $r = Data::RadixTree::Shared->new($p, 4096, 65536);
    is($r->count, 1, "reopening a valid file preserves its count");
    is($r->lookup("keep"), 99, "reopening a valid file preserves its data");
    undef $r; unlink $p;
}

done_testing;
