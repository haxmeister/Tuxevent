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


__END__
#ABSTRACT: O(1) multiplexing Event Loop for Linux using perl's new class feature

=pod

=head1 NAME

Tuxevent::Loop - O(1) multiplexing Event Loop for Linux

=head1 VERSION

version 0.001

=head1 SYNOPSIS

    use Tuxevent::Loop;
    my $tux = Tuxevent::Loop->new(
        signals => sub{
            $hashref = shift;
            # manage signals!
        },
    );

=head1 DESCRIPTION

Tuxevent::Loop is an Epoll based event loop with built in signal handling mechanism. Epoll is a multiplexing mechanism that scales up O(1) with number of watched files. This module began as a wrapper around Linux::Epoll to make it easily useable for programmers using the new class feature. Then it grew to include a ready made loop and it's own instance of Linux::FD::Signal. So as it were, the documentation for the Linux::Epoll methods is simply re-constituted here in the corresponding method wrappers and those will have the same functionality.


=head1 METHODS

=head2 new()

Create a new loop instance with the following possible parameters:

    # sigset - for the POSIX::SigSet to handle signals
    # Optional but if left out it will default to capture ALL signals

    # max - number of events to pull from epoll at a time
    # Optional, defaults to 64 a seemingly reasonable number

    # timeout - how long call to epoll waits for an event before returning
    # Optional, if not provided it will wait until there is an event from Epoll. Note that the call to Epoll is wrapped in a while loop that will may allow users to add events that cannot be monitored by epoll.

    # signals - call back for signals recieved
    # Optional but if left out you have no way to handle signals

    # a call to new() with all the parameters being used may look like this:

    use POSIX qw/sigprocmask SIGUSER1 SIG_SETMASK/;
    my $loop = Tuxevent::Loop->new(
        sigset  => POSIX::SigSet->new( &POSIX::SIGUSR1 ),
        max     => 128,           # will handle up to 128 events per loop iteration
        timeout => 1,             # fractional seconds
        signals => \&sig_handler, # callback to some function
    );

=head2 add($fh, $events, $callback)

Register the filehandle with the epoll instance and associate events C<$events> and callback C<$callback> with it. C<$events> may be either a string (e.g. C<'in'>) or an arrayref (e.g. C<[qw/in out hup/]>). If a filehandle already exists in the set and C<add> is called in non-void context, it returns undef and sets C<$!> to C<EEXIST>; if the file can't be waited upon it sets C<$!> to C<EPERM> instead. On all other error conditions an exception is thrown. The callback gets a single argument, a hashref whose keys are the triggered events.

=head2 modify($fh, $events, $callback)

Change the events and callback associated on this epoll instance with filehandle $fh. The arguments work the same as with C<add>. If a filehandle doesn't exist in the set and C<modify> is called in non-void context, it returns undef and sets C<$!> to C<ENOENT>. On all other error conditions an exception is thrown.

=head2 delete($fh)

Remove a filehandle from the epoll instance. If a filehandle doesn't exist in the set and C<delete> is called in non-void context, it returns undef and sets C<$!> to C<ENOENT>. On all other error conditions an exception is thrown.

=head2 wait($number = 1, $timeout = undef, $sigmask = undef)

Wait for up to C<$number> events, where C<$number> must be greater than zero. C<$timeout> is the maximal time C<wait> will wait for events in fractional seconds. If it is undefined it may wait indefinitely. C<$sigmask> is the signal mask during the call. If it is not defined the signal mask will be untouched. If interrupted by a signal it returns undef/an empty list and sets C<$!> to C<EINTR>. On all other error conditions an exception is thrown.

=head1 REQUIREMENTS

This module requires at least Perl 5.10 and Linux 2.6.19 to function correctly.

=head1 SEE ALSO

=over 4

=item * L<Linux::Epoll>

=item * L<Posix>

=item * L<Linux::FD>

=back

=head1 AUTHOR

Joshua S. Day <HAX@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2025 by Joshua S. Day.
This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
