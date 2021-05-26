package Koha::Plugin::Es::Xercode::ListsManager;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use utf8;
use C4::Context;
use C4::Members;
use C4::Biblio;
use C4::Items;
use C4::Auth;
use C4::Reports::Guided;
use C4::External::Depo;
use Koha::DateUtils;
use MARC::Record;
use JavaScript::Minifier qw(minify);
use Pod::Usage;
use Text::CSV::Encoded;
use C4::Utils::DataTables qw( dt_get_params );
use C4::Utils::DataTables::VirtualShelves qw( search );
use JSON;

use constant ANYONE => 2;

BEGIN {
    use Config;
    use C4::Context;

    my $pluginsdir  = C4::Context->config('pluginsdir');
}

our $VERSION = "1.0.0";

our $metadata = {
    name            => 'Lists Manager',
    author          => 'Xercode Media Software S.L.',
    description     => 'Lists Manager Plugin',
    date_authored   => '2021-05-26',
    date_updated    => '2020-05-26',
    minimum_version => '18.11',
    maximum_version => undef,
    version         => $VERSION,
};

our $dbh = C4::Context->dbh();


sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;
    
    my $self = $class->SUPER::new($args);

    return $self;
}

sub tool {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $userid     = C4::Context->userenv ? C4::Context->userenv->{number} : undef;
    my $branchcode = C4::Context->userenv ? C4::Context->userenv->{branch} : undef;
    
    my $template = $self->get_template( { file => 'tool.tt' } );
    if ( $self->retrieve_data('enabled') ) {
        $template->param(enabled => 1);
    }
    
    print $cgi->header(
        {
            -type     => 'text/html',
            -charset  => 'UTF-8',
            -encoding => "UTF-8"
        }
    );
    print $template->output();
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    warn Data::Dumper::Dumper($self->get_qualified_table_name('log'));
    if ( $cgi->param('save') ) {
        my $enabled = $cgi->param('enabled') ? 1 : 0;
        my $database_internal_use = $cgi->param('database_internal_use') ? 1 : 0;
        $self->store_data(
            {
                enabled => $enabled
            }
        );
        $self->go_home();
    }
    else {
        my $template = $self->get_template( { file => 'configure.tt' } );

        $template->param(
            enabled               => $self->retrieve_data('enabled')
        );
        
        print $cgi->header(
            {
                -type     => 'text/html',
                -charset  => 'UTF-8',
                -encoding => "UTF-8"
            }
        );
        print $template->output();
    }
}

sub install() {
    my ( $self, $args ) = @_;
    
    my $dbh = C4::Context->dbh;

    my $table_log = $self->get_qualified_table_name('log');
    $dbh->do(
        qq{
            CREATE TABLE `$table_log` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `borrowernumber` int(11) NOT NULL,
              `date_time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
              `shelfnumber` int(11) NOT NULL,
              `shelfname` varchar(255) NOT NULL,
              `action` varchar(20) NOT NULL,
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        }
    );
    
    return 1;
}

sub uninstall() {
    my ( $self, $args ) = @_;

    my $table_log = $self->get_qualified_table_name('log');
    C4::Context->dbh->do("DROP TABLE $table_log");
    
    return 1;
}

############################################
#                                          #
#              PLUGIN METHODS              #
############################################

sub trim {
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

sub search {
    my ($self, $params) = @_;
    my $input = $self->{'cgi'};

    my $shelfname = $input->param('shelfname');
    my $count = $input->param('count');
    my $owner = $input->param('owner');
    my $type = $input->param('type');
    my $sortby = $input->param('sortby');

    # variable information for DataTables (id)
    my $sEcho = $input->param('sEcho');

    my %dt_params = dt_get_params($input);
    foreach (grep {$_ =~ /^mDataProp/} keys %dt_params) {
        $dt_params{$_} =~ s/^dt_//;
    }

    my $results = C4::Utils::DataTables::VirtualShelves::search(
        {
            shelfname => $shelfname,
            count => $count,
            owner => $owner,
            type => $type,
            sortby => $sortby,
            dt_params => \%dt_params,
        }
    );
    
    my $template = $self->get_template( { file => 'shelvesresults.tt' } );
    $template->param(
        sEcho => $sEcho,
        iTotalRecords => $results->{iTotalRecords},
        iTotalDisplayRecords => $results->{iTotalDisplayRecords},
        aaData => $results->{shelves}
    );
    
    print $input->header(
        {
            -type     => 'application/json',
            -charset  => 'UTF-8',
            -encoding => "UTF-8"
        }
    );
    print $template->output();
}

sub removeshelves {
    my ($self, $params) = @_;
    my $cgi = $self->{'cgi'};
    
    my $data = from_json($cgi->param('data'));
    my $loggedinuser = C4::Context->userenv ? C4::Context->userenv->{number} : undef;
    
    my @messages;

    foreach (@{$data}){
        my $shelf       = Koha::Virtualshelves->find($_);
        if ($shelf) {
            if ( $shelf->can_be_deleted( $loggedinuser ) ) {
                eval { $shelf->delete; };
                if ($@) {
                    push @messages, { shelfid => $_, type => 'alert', code => ref($@), msg => $@ };
                } else {
                    push @messages, { shelfid => $_, type => 'message', code => 'success_on_delete' };
                    # Save log
                    my $table_log = $self->get_qualified_table_name('log');
                    $dbh->do(
                        qq{
                                INSERT INTO $table_log (`borrowernumber`, `shelfnumber`, `shelfname`, `action` ) VALUES ( ?, ?, ?, ? );
                            }
                        , undef, ( $loggedinuser, $shelf->shelfnumber, $shelf->shelfname, "remove" ));
                }
            } else {
                push @messages, { shelfid => $_, type => 'alert', code => 'unauthorized_on_delete' };
            }
        } else {
            push @messages, { shelfid => $_, type => 'alert', code => 'does_not_exist' };
        }
    }
    
    print $cgi->header( -type => 'application/json', -charset => 'utf-8' );
    print to_json({'result' => \@messages});
}

1;

__END__

=head1 NAME

ListsManager.pm - Lists Manager Koha Plugin.

=head1 SYNOPSIS

Lists Manager

=head1 DESCRIPTION

Lists Manager Plugin

=head1 AUTHOR

Juan Francisco Romay Sieira <juan.sieira AT xercode DOT es>

=head1 COPYRIGHT

Copyright 2021 Xercode Media Software S.L.

=head1 LICENSE

This file is part of Koha.

Koha is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later version.

You should have received a copy of the GNU General Public License along with Koha; if not, write to the Free Software Foundation, Inc., 51 Franklin Street,
Fifth Floor, Boston, MA 02110-1301 USA.

=head1 DISCLAIMER OF WARRANTY

Koha is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=cut
