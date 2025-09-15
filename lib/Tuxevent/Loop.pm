# lib/Tuxevent/Loop.pm
use v5.42;
use feature 'class';
no warnings 'experimental::class';


use Linux::Epoll;
use Linux::FD::Signal;


class Tuxevent::Loop;
use Data::Printer;
use POSIX qw/sigprocmask SIG_SETMASK/;
# for the Linux::Epoll object to handle file descriptor events
field $epoll :reader;

# for the POSIX::Sigset to handle signals
field $sigset :param :reader = undef;

# for the Linux::FD::Signal to pass signals to loop events
field $fdsignal :reader;

# max number of events to pull from epoll at a time
field $max :param  :reader :writer  = 64;

# how long call to epoll waits an event before returning
field $timeout :param  :reader :writer  = undef;

# call back for signals recieved
field $signals :param :writer = undef;

# looper stopper
field $stopped = 0;

ADJUST{
    # our new epoll handle
    $epoll = Linux::Epoll->new();

    # use a provided SigSet or generate one with all signals added
    unless (defined $sigset){
        say "filling sigset";
        $sigset = POSIX::SigSet->new() or die $!;
        $sigset->fillset() or die $!;

    }

    # use the sigset to mask signals
    sigprocmask(SIG_SETMASK, $sigset) or die $!;

    # our new signals handle
    $fdsignal  = Linux::FD::Signal->new( $sigset, 'non-blocking');

    # add the signals  handle to epoll and set it to call back
    # the signals method to be dealt with
    $self->add( $fdsignal, ['in'], sub {
        $self->rec_signal( $fdsignal->receive() );
    } );
    say "add success???";
}

method add ($handle, $events, $callback) {
    return $epoll->add($handle, $events, $callback);
}

method modify( $fh, $events, $cb ) {
    return $epoll->modify($fh, $events, $cb)
}

method delete($fh){
    return $epoll->delete($fh);
}

# loop stop
method stop(){
    $stopped = 1;
}

# the method called when a signal is captured
method rec_signal($sigs){
    try{
        $signals->($sigs);
    }
    catch ($error){
        warn "Signal handler not defined: $!";
    }
}

# change the sigset
method set_sigset($new_sigset){
    $sigset = $new_sigset;

    # attempt to change the mask to the new sigset
    return sigprocmask(SIG_SETMASK, $new_sigset) ;
}

# Run while not stopped
method run (){
    while (! $stopped) {
        $self->wait();
    }
}

# single loop iteration
method wait(){
    say "process id: $$";
    # TODO handle epoll errors
    $epoll->wait($max, $timeout, $sigset) or die $!;
}



1;
