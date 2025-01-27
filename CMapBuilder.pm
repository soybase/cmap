package CMapBuilder;

=head1 NAME

CMapBuilder

=head1 DESCRIPTION

This is the builder/installer module for CMap.  It use Module::Build.

=cut

use strict;
use Cwd;
use CGI;
use File::Basename;
use File::Copy;
use File::Find;
use File::Path;
use File::Spec::Functions qw( catfile catdir abs2rel );
use FindBin;
use Module::Build;
use Test::Harness;
use Pod::Html;
use Config;

use base 'Module::Build';

# ----------------------------------------------------
sub ACTION_test {
    my $self = shift;

    use constant DATASOURCE => 'CMAP_INSTALL_TEST';
    use lib "$FindBin::Bin/lib";
    $ENV{'CMAP_ROOT'} = $FindBin::Bin;
    require DBD::SQLite;
    require Bio::GMOD::CMap::Admin;
    require Bio::GMOD::CMap::Admin::Import;
    require Bio::GMOD::CMap::Admin::MakeCorrespondences;

    # Create config
    $self->ACTION_create_sqlite_db(DATASOURCE, "$FindBin::Bin/t/CMAP_INSTALL_TEST.db")
        or die "Failed to create the SQLite database\n";

    $self->notes( 'DATASOURCE', DATASOURCE );

    $self->run_perl_script( catfile( 'conf', 'post_install_test.conf.PL' ) );
    my $conf_file = 'post_install_test.conf';
    my $from_conf = catfile( 'conf', $conf_file );
    my $to_conf   = catfile( "$FindBin::Bin/t/", 'CMAP_INSTALL_TEST.conf' );
    $self->copy_if_modified(
        from    => $from_conf,
        to      => $to_conf,
        flatten => 0,
    );

    # Add data
    my $config = Bio::GMOD::CMap::Config->new( config_dir => "$FindBin::Bin/t/" );
    my $admin = Bio::GMOD::CMap::Admin->new( data_source => DATASOURCE, config => $config ) ;
    die
        "The config file for the new Data Source (" . DATASOURCE . ") did not get properly installed\n"
        unless ( DATASOURCE eq $admin->data_source() );

    $self->SUPER::ACTION_test;

    # Purge Cache 'cause what the heck.
    $admin->purge_cache(1);

    #if ( $self->y_n( "\nDelete the test files and database?", 'y' ) ) {
    #}

    return;
}

# ----------------------------------------------------
sub ACTION_install {
    my $self = shift;
    my %args = map { $_, 1 } @{ $self->{'args'}{'ARGV'} || [] };
    $self->ACTION_install_html unless $args{'nohtml'};
    $self->ACTION_templates    unless $args{'notemplates'};

    #
    # Install config file.
    #
    unless ( $args{'noconf'} ) {
        my $conf_dir = $self->notes('CONF');
        unless ( -d $conf_dir ) {
            eval { mkpath( $conf_dir, 0, 0755 ) };
            warn "Can't create conf dir $conf_dir: $@\n" if $@;
        }

        my $copy_conf = 1;
        my $to_conf = catfile( $conf_dir, 'global.conf' );
        if ( -e $to_conf ) {
            $copy_conf
                = $self->y_n( "'$to_conf' exists.  Overwrite?", 'n' );
        }

        if ( $copy_conf ) {
            $self->run_perl_script([], 'conf/global.conf.PL', [$conf_dir]);
        }

        foreach my $conf_file ( 'example.conf' ) {
            my $from_conf = catfile( 'conf',    $conf_file );
            my $to_conf   = catfile( $conf_dir, $conf_file );
            my $copy_conf = 1;
            if ( -e $to_conf ) {
                $copy_conf
                    = $self->y_n( "'$to_conf' exists.  Overwrite?", 'n' );
            }

            $self->copy_if_modified(
                from    => $from_conf,
                to      => $to_conf,
                flatten => 0,
            ) if $copy_conf;
        }
    }

    #
    # Install the CGI script.
    #
    my $from_cgi = 'cgi-bin/cmap';
    my $to_cgi = catfile( $self->notes('CGIBIN'), 'cmap' );

    my $copy_cgi = 1;
    if ( -e $to_cgi ) {
        $copy_cgi = $self->y_n( "'$to_cgi' exists.  Overwrite?", 'n' );
    }

    $self->copy_if_modified(
        from    => $from_cgi,
        to      => $to_cgi,
        flatten => 0,
    ) if $copy_cgi;
    chmod 0755, $to_cgi or die "Cannot make '$to_cgi' executable: $!\n";

    #
    # Make the temp dir for the images
    #
    my $cache_dir = $self->notes('CACHE');
    unless ( -d $cache_dir ) {
        eval { mkpath( $cache_dir, 0, 0777 ) };

        # mkpath won't give more permissive permissions than the parent
        chmod 0777, $cache_dir
            or die "Cannot make '$cache_dir' read/write/executable: $!\n";
        warn "Can't create image cache dir $cache_dir: $@\n" if $@;
    }

    #
    # Make the temp dir for the sessions
    #
    my $session_dir = $self->notes('SESSIONS');
    unless ( -d $session_dir ) {
        eval { mkpath( $session_dir, 0, 0777 ) };

        # mkpath won't give more permissive permissions than the parent
        chmod 0777, $session_dir
            or die "Cannot make '$session_dir' read/write/executable: $!\n";
        warn "Can't create image session dir $session_dir: $@\n" if $@;
    }

    $self->SUPER::ACTION_install;

    if ($self->y_n(
            "Would you like to set up a demo datasource?  This will require you to have access to a database system.",
            'n'
        )
        )
    {
        $self->ACTION_demo();
    }
    else {
        print
            q[If you would like to set up the demo in the future, simply run ]
            . q["./Build demo" with aministrator privileges.\n];
    }

    chomp( my $host = `hostname` || 'localhost' );
    print join( "\n\n",
        '',
        'CMap has been installed at http://$host/cmap',
        "Please, read http://$host/cmap/INSTALL.html to find out how to complete the installation process.",
        "Then refer to http://$host/cmap/ADMINISTRATION.html "
            . "for information on how to configure CMap, load data "
            . "and purge the cache.!",
        '' );
    return;
}

# ----------------------------------------------------
sub ACTION_realclean {
    my $self = shift;
    $self->delete_filetree('cmap_install.conf');
    $self->SUPER::ACTION_realclean;
}

# ----------------------------------------------------
sub ACTION_html {
    my $self = shift;
    my $cwd  = cwd();

    #
    # Turn all POD files into HTML and install into "htdocs."
    #
    my ( @pod_files, @cleanup );
    find(
        sub {
            return if ( $File::Find::name =~ /upgrade/ );
            push @pod_files, $File::Find::name
                if -f $_ && $File::Find::name =~ /\.pod$/;
        },
        $cwd
    );

    #
    # Prepare a list of the base files to include in the default index page.
    #
    my @html_links = (
        [ '/cmap/viewer',      'CMap Viewer' ],
        [ '/cmap/admin',       'Web Admin Tool' ],
        [ 'tutorial/', 'User Tutorial' ],
        [ 'admintut/', 'Admin Tutorial' ],
    );

    for my $pod (@pod_files) {
        my $filename = basename $pod;
        my $outfile  = $filename;
        $filename =~ s/[_-]/ /g;
        $filename =~ s/\.pod$//;
        $outfile  =~ s/\.pod$/\.html/;
        my $outpath = catfile( $cwd, 'htdocs', $outfile );
        print "pod2html $pod -> $outpath\n";
        pod2html(
            "--infile=$pod", "--outfile=$outpath", "--backlink",
            "--title=$filename",
            "--css=" . $self->notes('HTDOCS') . "/pod-style.css",
        );
        push @html_links, [ $outfile, $filename ];
        push @cleanup, $outpath;
    }

    #
    # Find all the relevant "docs" and install them into "htdocs."
    #
    my @doc_files;
    find(
        sub {
            push @doc_files, $File::Find::name
                if -f $_ && $File::Find::name =~ /\.(png|html)$/;
        },
        'docs'
    );

    for my $file (@doc_files) {
        my $filename = basename $file;
        my $outpath = catfile( $cwd, 'htdocs', $filename );
        print "$file -> $outpath\n";
        copy( $file, $outpath ) unless -e $outpath;
        push @html_links, [ $filename, $filename ];
        push @cleanup, $outpath;
    }

    $self->add_to_cleanup(@cleanup);

    #
    # Create the main CMap index page with a summary of the install.
    #

    my $index = catfile( 'htdocs', 'index.html' );
    open INDEX, ">$index" or die "Can't write new index file '$index': $!\n";
    my $q      = CGI->new;
    my $title  = 'CMap Installation Summary';
    my $navbar = join(
        '&nbsp;|&nbsp;',
        map {
                  $_->[1]
                ? $q->a( { -href => $_->[1] }, $_->[0] )
                : $q->b( $_->[0] )
            } (
            [ 'CMap Home'      => '' ],
            [ 'Maps'           => '/cmap/viewer' ],
            [ 'Map Search'     => '/cmap/map_search' ],
            [ 'Feature Search' => '/cmap/feature_search' ],
            [ 'Matrix'         => '/cmap/matrix' ],
            [ 'Map Sets'       => '/cmap/map_set_info' ],
            [ 'Feature Types'  => '/cmap/feature_type_info' ],
            [ 'Map Types'      => '/cmap/map_type_info' ],
            [ 'Evidence Types' => '/cmap/evidence_type_info' ],
            [ 'Species'        => '/cmap/species_info' ],
            [ 'Help'           => '/cmap/help' ],
            [ 'Tutorial'       => 'tutorial/' ],
            )
    );

    print "Creating htdocs/index.html\n";
    print INDEX join(
        "\n",
        $q->start_html( { -title => $title, -style => 'cmap.css' } ),
        $q->h1($title),
        $q->br,
        "<!-- Here's a sample navigation bar you may want to use. -->",
        $navbar,
        "<!-- End CMap navbar -->",
        $q->p('Congratulations!  CMap has been installed.'),
        $q->p(
                  'Eventually you will want to create your own content '
                . 'for this intro page.'
        ),
        $q->p('Start using CMap with one of the following options.'),
        $q->ul(
            $q->li(
                $q->a( { -href => '/cmap/viewer' }, 'Maps' )
                    . " - Use a menu to select your starting maps\n"
            ),
            $q->li(
                $q->a( { -href => '/cmap/map_search' },
                    'Map Search' )
                    . " - If the map set is quite large, the Map Search page can be quicker than sorting through menus.\n"
            ),
            $q->li(
                $q->a( { -href => '/cmap/feature_search' },
                    'Feature Search' )
                    . " - Search for a specific feature and display it on a map.\n"
            ),
            $q->li(
                $q->a( { -href => '/cmap/matrix' }, 'Matrix' )
                    . " - View a table of the number of correspondences between pairs of map sets and maps.\n"
            ),
        ),
        $q->p(
            'For an introduction to the basic consepts of CMap, please see the '
                . $q->a( { -href => '/cmap/help' }, 'help pages' )
                . ' or the '
                . $q->a( { -href => 'tutorial' },
                'tutorial' )
                . ".\n"
        ),
        $q->p(
            'We would appreciate you would include an acknowlegement of CMap '
                . 'on this page, e.g.:'
        ),
        $q->p(
            $q->a(
                { -href => 'http://gmod.org/wiki/CMap' },
                'CMap is free software from the GMOD project'
            )
        ),
        $q->p(
                  'For the mean time, here are some links to the installed '
                . 'application and supporting docs:'
        ),
        $q->ul(
            (   map {
                    $q->li( $q->a( { -href => $_->[0] }, $_->[1] ) ) . "\n"
                    } @html_links
            )
        ),
        'CMap was installed on ' . scalar localtime,
        $q->br,
        $q->a(
            { -href => 'http://www.gmod.org' },
            $q->img(
                {   -src => 'gmod_logo.jpg',
                    -alt => 'Powered by GMOD',
                }
            )
        ),
        '<hr>',
        'CMap is part of the <a href="http://www.gmod.org/">GMOD</a> project',
        $q->end_html,
        ''
    );
    close INDEX;
}

# ----------------------------------------------------
sub ACTION_install_html {
    my $self   = shift;
    my $to_dir = $self->notes('HTDOCS');
    my $from   = 'htdocs';
    my @htdocs = $self->read_dir($from);
    for my $file (@htdocs) {
        my $to = $to_dir;
        if ( $file =~ /($from)(.*)/ ) {
            $to = catdir( $to, $2 );
        }

        if ( $file =~ m{htdocs/index\.html$} && -e $to ) {
            next unless $self->y_n( "'$to' exists.  Overwrite?", 'n' );
        }

        $self->copy_if_modified(
            from    => $file,
            to      => $to,
            flatten => 0,
        );
    }
}

# ----------------------------------------------------
sub ACTION_templates {
    my $self      = shift;
    my $to_dir    = $self->notes('TEMPLATES');
    my $from      = 'templates';
    my @templates = $self->read_dir($from);

    for my $file (@templates) {
        my $to = $to_dir;
        if ( $file =~ /($from)(.*)/ ) {
            $to = catdir( $to, $2 );
        }

        $self->copy_if_modified(
            from    => $file,
            to      => $to,
            flatten => 0,
        );
    }
}

# ----------------------------------------------------
sub ACTION_demo {
    my $self = shift;

    require Bio::GMOD::CMap::Admin;
    require Bio::GMOD::CMap::Admin::Import;
    require Bio::GMOD::CMap::Admin::MakeCorrespondences;

    # Get DB info and create config
    my $windows = $Config{osname} =~ /mswin/i;
    if (!$windows
        and $self->y_n(
            "\nSet up a new mysql database "
                . "(must have root access to a current MySQL system)?",
            'n'
        )
        )
    {
        $self->ACTION_create_mysql_db('CMAP_DEMO')
            or die "Failed to create the mysql database\n";
    }
    else {
        unless (
            $self->y_n(
                "\nIf you have set up a database for the demo to use, "
                    . "you may proceed.\n"
                    . "If not, please create a database and create the CMap "
                    . "tables in it.  To do this in MySQL, it looks like this:\n"
                    . "    \$ mysql -uroot -p -e 'create database CMAP'\n"
                    . "    \$ mysql -uroot -p CMAP < sql/cmap.create.mysql\n"
                    . "    \$ mysql -uroot -p CMAP -e 'grant select, insert, "
                    . "update, delete\n"
                    . "      on CMAP.* to joe\@localhost identified by \"foobar\"'\n"
                    . "    \$ mysqladmin -uroot -p flush-privileges\n\n"
                    . "Have you set up a database for CMap?",
                'y'
            )
            )
        {
            die "I'm sorry but to set up a CMap demo, "
                . "you must have a database system.\n  When you "
                . "have done so, please run \"Build demo\" "
                . "to set up the demo.\n";
        }

        my $dns_str = $self->prompt(
            "\nThe DNS string is the string passed to DBI to connect to the "
                . "database, e.g.,\n"
                . "   MySQL: \"dbi:mysql:CMAP\" \n"
                . "   PostgreSQL: \"dbi:Pg:dbname=cmap\" \n"
                . "What is the DNS string for the database you wish to "
                . "store the demo data in (required)?\n",
            'dbi:mysql:CMAP_DEMO'
        );
        die "Need a DNS string to continue\n" unless ($dns_str);
        my $db_user = $self->prompt(
            "\nWhat is the user name that will be used to connect with the database (required)?\n",
            'mysql'
        );
        die "Need a database username to continue\n" unless ($db_user);
        my $db_pass = $self->prompt(
            "\nWhat is the password that will be used to connect with the database?\n",
            q{}
        );
        $self->notes( 'DNS_STR', $dns_str, );
        $self->notes( 'DB_USER', $db_user, );
        $self->notes( 'DB_PASS', $db_pass, );
    }
    my $datasource = $self->prompt(
        "\nThe data source name is what this database will be refered to as "
            . "in CMap.  You may name it any word you like.\n"
            . "What should the demo data source be named? ",
        'CMAP_DEMO'
    );
    die "Need a data source to continue\n" unless ($datasource);
    $self->notes( 'DATASOURCE', $datasource, );

    $self->run_perl_script( catfile( 'conf', 'demo.conf.PL' ) );
    my $conf_dir  = $self->notes('CONF');
    my $conf_file = 'demo.conf';
    my $from_conf = catfile( 'conf', $conf_file );
    my $to_conf   = catfile( $conf_dir, $conf_file );
    $self->copy_if_modified(
        from    => $from_conf,
        to      => $to_conf,
        flatten => 0,
    );

    # Add data
    my $admin = Bio::GMOD::CMap::Admin->new( data_source => $datasource, );
    die
        "The config file for the new Data Source ($datasource) did not get properly installed\n"
        unless ( $datasource eq $admin->data_source() );

    # Create the Species
    my $species_id = $admin->species_create(
        species_acc         => 'TEST_SPECIES',
        species_common_name => 'Test Species',
        species_full_name   => 'Testus speciesus',
    ) or die "Error: ", $admin->error, "\n";

    # Create Map Sets
    my $map_set_id1 = $admin->map_set_create(
        map_set_name       => 'Test Data 1',
        map_set_short_name => 'Test Data 1',
        species_id         => $species_id,
        map_type_acc       => 'Seq',
        map_set_acc        => 'TD1',
    ) or die "Error: ", $admin->error, "\n";
    my $map_set_id2 = $admin->map_set_create(
        map_set_name       => 'Test Data 2',
        map_set_short_name => 'Test Data 2',
        species_id         => $species_id,
        map_type_acc       => 'Seq',
        map_set_acc        => 'TD2',
    ) or die "Error: ", $admin->error, "\n";

    # Import Files
    my $importer
        = Bio::GMOD::CMap::Admin::Import->new( data_source => $datasource, );
    my $file1 = catfile( 'data', 'tabtest1' );
    my $file2 = catfile( 'data', 'tabtest2' );
    my $fh = IO::File->new($file1) or die "Can't read $file1: $!";
    $importer->import_tab(
        map_set_id   => $map_set_id1,
        fh           => $fh,
        map_type_acc => 'Seq',
        overwrite    => 1,
        allow_update => 0,
    ) or die "Error: ", $importer->error, "\n";
    $fh = IO::File->new($file2) or die "Can't read $file2: $!";
    $importer->import_tab(
        map_set_id   => $map_set_id2,
        fh           => $fh,
        map_type_acc => 'Seq',
        overwrite    => 1,
        allow_update => 0,
    ) or die "Error: ", $importer->error, "\n";

    # Create Correspondences
    my $corr_maker = Bio::GMOD::CMap::Admin::MakeCorrespondences->new(
        data_source => $datasource, );

    my @skip_feature_type_accs = ( 'read_depth', );
    $corr_maker->make_name_correspondences(
        evidence_type_acc      => 'ANB',
        from_map_set_ids       => [$map_set_id1],
        to_map_set_ids         => [$map_set_id2],
        skip_feature_type_accs => \@skip_feature_type_accs,
        quiet                  => 1,
        name_regex             => '(\S+)\.\w\d$',
        allow_update           => 0,
    ) or die "Error: ", $corr_maker->error, "\n";

    # Purge Cache 'cause what the heck.
    $admin->purge_cache(1);

    chomp( my $host = `hostname` || 'localhost' );
    print join( "\n\n",
        '',
        'The demo installation is complete.\n',
        qq[You can now go to "http://$host/cmap" to start learning about CMap.],
        '' );
}

# ----------------------------------------------------
sub ACTION_post_install_test {
    my $self = shift;

    require Bio::GMOD::CMap::Admin;
    require Bio::GMOD::CMap::Admin::Import;
    require Bio::GMOD::CMap::Admin::MakeCorrespondences;

    # Get DB info and create config
    my $windows = $Config{osname} =~ /mswin/i;
    if (!$windows
        and $self->y_n(
            "\nSet up a new mysql database to run tests on"
                . "(must have root access to a current MySQL system)?",
            'y'
        )
        )
    {
        $self->ACTION_create_mysql_db('CMAP_POST_INSTALL_TEST')
            or die "Failed to create the mysql database\n";
    }
    else {
        unless (
            $self->y_n(
                "\nIf you have set up a database for the test to use, "
                    . "you may proceed.\n"
                    . "If not, please create a database and create the CMap "
                    . "tables in it.  To do this in MySQL, it looks like this:\n"
                    . "    \$ mysql -uroot -p -e 'create database CMAP'\n"
                    . "    \$ mysql -uroot -p CMAP < sql/cmap.create.mysql\n"
                    . "    \$ mysql -uroot -p CMAP -e 'grant select, insert, "
                    . "update, delete\n"
                    . "      on CMAP.* to joe\@localhost identified by \"foobar\"'\n"
                    . "    \$ mysqladmin -uroot -p flush-privileges\n\n"
                    . "Have you set up a database for CMap?",
                'y'
            )
            )
        {
            die "I'm sorry but to set up a CMap demo, "
                . "you must have a database system.\n  When you "
                . "have done so, please run \"Build demo\" "
                . "to set up the demo.\n";
        }

        my $dns_str = $self->prompt(
            "\nThe DNS string is the string passed to DBI to connect to the "
                . "database, e.g.,\n"
                . "   MySQL: \"dbi:mysql:CMAP\" \n"
                . "   PostgreSQL: \"dbi:Pg:dbname=cmap\" \n"
                . "What is the DNS string for the database you wish to "
                . "store the demo data in (required)?\n",
            'dbi:mysql:CMAP_DEMO'
        );
        die "Need a DNS string to continue\n" unless ($dns_str);
        my $db_user = $self->prompt(
            "\nWhat is the user name that will be used to connect with the database (required)?\n",
            'mysql'
        );
        die "Need a database username to continue\n" unless ($db_user);
        my $db_pass = $self->prompt(
            "\nWhat is the password that will be used to connect with the database?\n",
            q{}
        );
        $self->notes( 'DNS_STR', $dns_str, );
        $self->notes( 'DB_USER', $db_user, );
        $self->notes( 'DB_PASS', $db_pass, );
    }
    my $datasource = $self->prompt(
        "\nThe data source name is what this database will be refered to as "
            . "in CMap.  You may name it any word you like.\n"
            . "What should the demo data source be named? ",
        'CMAP_POST_INSTALL_TEST'
    );
    die "Need a data source to continue\n" unless ($datasource);
    $self->notes( 'DATASOURCE', $datasource, );

    $self->run_perl_script( catfile( 'conf', 'post_install_test.conf.PL' ) );
    my $conf_dir  = $self->notes('CONF');
    my $conf_file = 'post_install_test.conf';
    my $from_conf = catfile( 'conf', $conf_file );
    my $to_conf   = catfile( $conf_dir, $conf_file );
    $self->copy_if_modified(
        from    => $from_conf,
        to      => $to_conf,
        flatten => 0,
    );

    # Add data
    my $admin = Bio::GMOD::CMap::Admin->new( data_source => $datasource, );
    die
        "The config file for the new Data Source ($datasource) did not get properly installed\n"
        unless ( $datasource eq $admin->data_source() );

    $self->SUPER::ACTION_test;

    # Purge Cache 'cause what the heck.
    $admin->purge_cache(1);

    #if ( $self->y_n( "\nDelete the test files and database?", 'y' ) ) {
    #}

}

# ----------------------------------------------------
sub ACTION_create_sqlite_db {
    my $self = shift;
    my $data_source = shift;
    my $db_pathname = shift;
    my $command;

    print "Dropping the database $db_pathname if it exists...\n";
    eval unlink($db_pathname); 

    $command = "sqlite3 $db_pathname < $FindBin::Bin/sql/cmap.create.sqlite";
    print "Running: $command\n";
    unless ( system($command) == 0 ) {
        die "$! $?\n";
    }

    $self->notes( 'DB_USER', '', );
    $self->notes( 'DB_PASS', '', );
    $self->notes( 'DNS_STR', "dbi:SQLite:dbname=$db_pathname", );

    return 1;
}

# ----------------------------------------------------
sub ACTION_create_mysql_db {
    my $self = shift;
    my $default_db_name = shift || 'CMAP_DEMO';
    my $command;
    my $db_name
        = $self->prompt(
        "\nWhat should the name of the database be (required)?\n",
        $default_db_name );
    die "Need a database username to continue\n" unless ($db_name);
    my $dns_str_no_db = $self->prompt(
        "\nWhat is the DNS string to be passed to DBI to connect to the "
            . "MySQL server (without the database name), e.g.,"
            . " \"dbi:mysql:\" "
            . "(required)?\n",
        'dbi:mysql:'
    );
    die "Need a DNS string to continue\n" unless ($dns_str_no_db);
    my $dns_str = $dns_str_no_db . $db_name;

    # Initiate DB connection
    my $options = {
        AutoCommit       => 1,
        FetchHashKeyName => 'NAME_lc',
        LongReadLen      => 3000,
        LongTruncOk      => 1,
        RaiseError       => 1,
    };

    my $db_user = $self->prompt(
        "\nWhat is the user name that will be used to connect with the database (required)?\n",
        'mysql'
    );
    die "Need a database username to continue\n" unless ($db_user);
    my $db_pass = $self->prompt(
        "\nWhat is the password that will be used to connect with the database?\n",
        q{}
    );

    my $root_db_pass = $self->prompt(
        "\nWhat is the root password that will be used to create the database?\n",
        q{}
    );
    my $root_pass_str = '';
    $root_pass_str = "-p'$root_db_pass'" if ($root_db_pass);

    print "Dropping the database $db_name if it exists...\n";
    eval
        qq{system("mysql -uroot $root_pass_str -e 'drop database $db_name'")};
    foreach my $command_list (
        [   qq{mysql -uroot $root_pass_str -e 'create database $db_name'},
            "Problem creating database: "
        ],
        [   qq{mysql -uroot $root_pass_str $db_name < sql/cmap.create.mysql},
            "Problem reading sql file: "
        ],
        [   (   $db_pass
                ? qq{mysql -uroot $root_pass_str $db_name -e }
                    . qq{'grant select, insert, update, delete }
                    . qq{on $db_name.* to $db_user}
                    . q{@localhost}
                    . qq{ identified by "$db_pass"'}
                : qq{mysql -uroot $root_pass_str $db_name -e }
                    . qq{'grant select, insert, update, delete }
                    . qq{on $db_name.* to $db_user}
                    . q{@localhost'}
            ),
            "Problem granting privileges: "
        ],
        [   qq{mysqladmin -uroot $root_pass_str flush-privileges},
            "Problem flushing privileges: "
        ],
        )
    {
        $command = $command_list->[0];
        print "Running: $command\n";
        unless ( system($command) == 0 ) {
            die $command_list->[1] . "$! $?\n";
        }
    }

    $self->notes( 'DB_USER', $db_user, );
    $self->notes( 'DB_PASS', $db_pass, );
    $self->notes( 'DNS_STR', $dns_str, );

    return 1;
}

# ----------------------------------------------------
sub read_dir {
    my $self = shift;
    my $dir  = shift;
    die "Directory '$dir' does not exist\n" unless -d $dir;

    my @files;
    find(
        sub {
            push @files, $File::Find::name
                if -f $_ && $File::Find::name !~ /CVS/;
        },
        $dir
    );

    return @files;
}

# ----------------------------------------------------

=pod

=head1 AUTHOR

Ben Faga E<lt>faga@cshl.eduE<gt>.
Ken Y. Clark E<lt>kclark@cshl.eduE<gt>.

=head1 COPYRIGHT

Copyright (c) 2004-7 Cold Spring Harbor Laboratory

This module is free software; you can redistribute it and/or modify it under
the terms of the GPL (either version 1, or at your option, any later version)
or the Artistic License 2.0.  Refer to LICENSE for the full license text and to
DISCLAIMER for additional warranty disclaimers.

=cut

1;

