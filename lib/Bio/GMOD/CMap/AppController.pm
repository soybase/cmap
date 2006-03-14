package Bio::GMOD::CMap::AppController;

# vim: set ft=perl:

# $Id: AppController.pm,v 1.2 2006-03-14 22:16:19 mwz444 Exp $

=head1 NAME

Bio::GMOD::CMap::AppController - Controller for the CMap Application.

=head1 SYNOPSIS


=head1 DESCRIPTION

This is the controlling module for the CMap Application.

=head1 METHODS

=cut

use strict;
use vars qw( $VERSION );
$VERSION = (qw$Revision: 1.2 $)[-1];

use Data::Dumper;
use Tk;
use Bio::GMOD::CMap;
use Bio::GMOD::CMap::Data::AppData;
use Bio::GMOD::CMap::Drawer::AppInterface;
use Bio::GMOD::CMap::Drawer::AppDisplayData;
use Bio::GMOD::CMap::Constants;

use base 'Bio::GMOD::CMap';

# ----------------------------------------------------
sub init {

=pod

=head2 init

Initializes the object.

=cut

    my ( $self, $config ) = @_;
    $self->params( $config, qw[ config_dir data_source ] );
    $self->config();
    $self->data_source( $self->{'data_source'} );
    my $window_acc = $self->start_application();
    $self->new_reference_maps( window_acc => $window_acc, );
    MainLoop();
    return $self;
}

# ----------------------------------------------------
sub start_application {

=pod
                                                                                                                             
=head2 start_application
                                                                                                                             
This method will create the Application.
                                                                                                                             
=cut

    my $self = shift;
    my $window_acc = $self->create_window( title => "CMap Application", )
        or die "Failed to create interface\n";
    my $app_display_data = $self->app_display_data();
    return $window_acc;
}

# ----------------------------------------------------
sub create_window {

=pod
                                                                                                                             
=head2 create_application
                                                                                                                             
This method will create the Application.
                                                                                                                             
=cut

    my $self      = shift;
    my $interface = $self->app_interface();
    my $window_acc
        = $interface->create_window( title => "CMap Application", );
    unless ( defined $window_acc ) {
        die "Problem setting up interface\n";
    }

    return $window_acc;
}

# ----------------------------------------------------
sub app_data_module {

=pod

=head3 app_data_module

Returns a handle to the data module.

=cut

    my $self = shift;

    $self->{'app_data_module'} = shift if @_;

    unless ( $self->{'app_data_module'} ) {
        $self->{'app_data_module'} = Bio::GMOD::CMap::Data::AppData->new(
            data_source => $self->data_source,
            config      => $self->config,
            )
            or $self->error( Bio::GMOD::CMap::Data::AppData->error );
    }

    return $self->{'app_data_module'};
}

# ----------------------------------------------------
sub app_interface {

=pod

=head3 app_interface

Returns a handle to the data module.

=cut

    my $self = shift;

    $self->{'app_interface'} = shift if @_;

    unless ( $self->{'app_interface'} ) {
        $self->{'app_interface'} = Bio::GMOD::CMap::Drawer::AppInterface->new(
            app_data_module => $self->app_data_module(),
            app_controller  => $self,
            )
            or die "Couldn't initialize AppInterface\n";
    }

    return $self->{'app_interface'};
}

# ----------------------------------------------------
sub app_display_data {

=pod

=head3 app_display_data

Returns a handle to the data module.

=cut

    my ( $self, %args ) = @_;

    unless ( $self->{'app_display_data'} ) {
        $self->{'app_display_data'}
            = Bio::GMOD::CMap::Drawer::AppDisplayData->new(
            data_source     => $self->data_source,
            app_data_module => $self->app_data_module,
            app_interface   => $self->app_interface,
            config          => $self->config,
            )
            or die "failed to create app_display_data\n";
    }

    return $self->{'app_display_data'};
}

# ----------------------------------------------------
sub new_reference_maps {

=pod

=head2 new_reference_maps


=cut

    my ( $self, %args ) = @_;
    my $window_acc = $args{'window_acc'}
        or die "no window acc for new_reference_maps";

    $self->app_interface()->select_reference_maps(
        window_acc => $window_acc,
        controller => $self,
    );

    return;

}

=pod

=head1 CallBack Methods

=cut

# ----------------------------------------------------
sub load_first_slot {

=pod

=head2 load_first_slot

Load the first slot of a page.

=cut

    my ( $self, %args ) = @_;

    my $selectable_ref_map_accs = $args{'selectable_ref_map_accs'} or return;
    my $selections              = $args{'selections'}              or return;
    my $window_acc              = $args{'window_acc'}              or return;

    my @selected_map_accs
        = map { $selectable_ref_map_accs->[$_] } @$selections;

    if (@selected_map_accs) {
        $self->app_display_data()->load_first_slot_of_window(
            window_acc => $window_acc,
            map_accs   => \@selected_map_accs,
        );
    }

    return;

}

# ----------------------------------------------------
sub close_window {

=pod

=head2 close_window

When window is closed, delete drawing data and if it is the last window, exit.

=cut

    my ( $self, %args ) = @_;
    my $window_acc = $args{'window_acc'};

    my $remaining_windows_num = $self->app_display_data()
        ->remove_window( window_acc => $window_acc, );

    unless ($remaining_windows_num) {
        exit;
    }

    return;
}

=pod

=head1 Extra Methods

=cut

# ----------------------------------------------------
sub xcheck_datasource_credentials {

=pod

=head2 check_datasource_credentials

See if we need to prompt for user/pass for the given datasource.  

This seems like it will be useful in the application too.  We'll keep it around
for now.

=cut

    my $self    = shift;
    my $ds      = $self->data_source() or return;
    my $config  = $self->config or return;
    my $db_conf = $config->get_config('database');

    #    if ( my $passwd_file = $db_conf->{'passwd_file'} ) {
    #        if ( my $cookie = $apr->cookie('CMAP_LOGIN') ) {
    #            my $sekrit = 'r1ce1sn2c3';
    #            my ( $user, $ds2, $auth ) = split( /:/, $cookie );
    #            return $ds                          eq $ds2
    #                && md5( $user . $ds . $sekrit ) eq $auth;
    #        }
    #        else {
    #            return 0;
    #        }
    #    }
    #    else {
    return 1;

    #    }
}

sub _order_out_from_zero {
    ###Return the sort in this order (0,1,-1,-2,2,-3,3,)
    return ( abs($a) cmp abs($b) );
}

1;

# ----------------------------------------------------
# If the fool would persist in his folly
# He would become wise.
# William Blake
# ----------------------------------------------------

=pod

=head1 SEE ALSO

L<perl>.

=head1 AUTHOR

Ken Y. Clark E<lt>kclark@cshl.orgE<gt>.

=head1 COPYRIGHT

Copyright (c) 2002-4 Cold Spring Harbor Laboratory

This library is free software;  you can redistribute it and/or modify 
it under the same terms as Perl itself.

=cut

