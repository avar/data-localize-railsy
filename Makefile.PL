use strict;
use ExtUtils::MakeMaker;

my $dist = 'Data::Localize::Railsy';
(my $s_dist = $dist) =~ s[::][/]g;
(my $h_dist = $dist) =~ s[::][-]g;

WriteMakefile(
    NAME          => $dist,
    AUTHOR        => 'Ævar Arnfjörð Bjarmason <avar@cpan.org>',
    ABSTRACT_FROM => 'lib/' . $s_dist . '.pm',
    VERSION_FROM  => 'lib/' . $s_dist . '.pm',
    LICENSE       => 'perl',
    META_MERGE => {
        build_requires => {
            'Test::More' => '0.94',
        },
        resources => {
            license => 'http://dev.perl.org/licenses/',
            repository => 'http://github.com/avar/' . lc($h_dist),
            bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=' . $h_dist,
        },
    },

    PREREQ_PM     => {
        # Catalyst/Plugin/Railsy.pm
        'Data::Localize' => '0.00011',
        'Moose' => '0.93',
    },
);
