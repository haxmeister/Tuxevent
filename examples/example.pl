#!/usr/bin/env perl

use v5.42;
use FindBin;
use lib "$FindBin::Bin/../lib";
use experimental qw(class);
no warnings 'experimental::class';

use Tuxevent::Loop;
use Linux::FD::Timer;
use Data::Printer;

my $Tux = Tuxevent::Loop->new(
    signals => \&sig_handler,
);

my $timer = Linux::FD::Timer->new('monotonic', 'non-blocking');
$timer->set_timeout(2, 2);

$Tux->add($timer,['in'], sub{my $flags = shift; timer_cb($flags)} );


sub timer_cb ($flags){
    my @drain = <$timer>;
    say "my timer cb";
}

sub sig_handler($signals){
    say "sig_handler fired in example";
    p $signals;
}

say "starting loop";
$Tux->run();


