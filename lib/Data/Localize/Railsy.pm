package Data::Localize::Railsy;
use Encode ();
use Moose;
use File::Basename ();
use File::Spec;
use File::Temp qw(tempdir);
use Data::Localize::Storage::Hash;
use YAML::Any qw(LoadFile);

our $VERSION = '0.02';

with 'Data::Localize::Localizer';

has 'encoding' => (
    is => 'rw',
    isa => 'Str',
    default => 'utf-8',
    lazy => 1,
);

has 'paths' => (
    traits => ['Array'],
    is => 'rw',
    isa => 'ArrayRef',
    trigger => sub {
        my $self = shift;
        $self->load_from_path($_) for @{$_[0]}
    },
    handles => {
        path_add => 'unshift',
    }
);

after 'path_add' => sub {
    my $self = shift;
    $self->load_from_path($_) for @{ $self->paths };
};

has 'storage_class' => (
    is => 'rw',
    isa => 'Str',
    default => sub {
        return '+Data::Localize::Storage::Hash';
    }
);

has 'storage_args' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { +{} }
);

has 'lexicon_map' => (
    traits => ['Hash'],
    is => 'rw',
    isa => 'HashRef[Data::Localize::Storage]',
    default => sub { +{} },
    handles => {
        lexicon_map_get => 'get',
        lexicon_map_set => 'set',
    }
);

sub BUILDARGS {
    my ($class, %args) = @_;

    my $path = delete $args{path};
    if ($path) {
        $args{paths} ||= [];
        push @{$args{paths}}, $path;
    }
    $class->SUPER::BUILDARGS(%args, style => 'maketext');
}

sub register {
    my ($self, $loc) = @_;
    $loc->add_localizer_map('*', $self);

}

sub load_from_path {
    my ($self, $path) = @_;

    return unless $path;

    if (Data::Localize::DEBUG()) {
        print STDERR "[Data::Localize::Railsy]: load_from_path - loading from glob($path)\n" 
    }

    foreach my $x (glob($path)) {
        $self->load_from_file($x) if -f $x;
    }
}

sub load_from_file {
    my ($self, $file) = @_;

    if (Data::Localize::DEBUG()) {
        print STDERR "[Data::Localize::Railsy]: load_from_file - loading from file $file\n"
    }

    my $lexicon = LoadFile( $file );
    my %lexicon = %{ _flatten_hash( $lexicon ) };

    my $lang = File::Basename::basename($file);
    $lang =~ s/\.ya?ml$//;

    if (Data::Localize::DEBUG()) {
        print STDERR "[Data::Localize::Railsy]: load_from_file - registering ",
            scalar keys %lexicon, " keys\n"
    }

    # This needs to be merged
    $self->lexicon_merge($lang, \%lexicon);
}

sub _flatten_hash
{
    my ($hash) = @_;

    # Remove the root $lang => key
    my @keys = keys %$hash;
    die "YAML hash had more than 1 root key" if @keys != 1;
    $hash = $hash->{$keys[0]};

    # Flatten it
    my $flat_hash = { _iterate($hash) };

    $flat_hash;
}

sub _iterate
{
    my ($hash, @path) = @_;
    my @ret;
        
    while (my ($k, $v) = each %$hash)
    {
        if (ref $v eq 'HASH')
        {
             push @ret => _iterate($v, @path, $k);
        }
        else
        {
            push @ret => join(".",@path, $k), $v;
        }
    }

    return @ret;
}

sub format_string {
    my ($self, $value, $args) = @_;

    if ($args) {
        die "\$args must be a HashRef" unless ref $args eq 'HASH';
    }

    while (my ($k, $v) = each %$args) {
        $value =~ s[ \{\{ \Q$k\E \}\} ][$v]gxs;
    }

    return $value;
}

sub _method {
    my ($self, $method, $embedded, $args) = @_;

    my @embedded_args = split /,/, $embedded;
    my $code = $self->can($method);
    if (! $code) {
        confess(blessed $self . " does not implement method $method");
    }
    return $code->($self, $args, \@embedded_args );
}

sub lexicon_get {
    my ($self, $lang, $id) = @_;
    my $lexicon = $self->lexicon_map_get($lang);
    return () unless $lexicon;
    $lexicon->get($id);
}

sub lexicon_set {
    my ($self, $lang, $id, $value) = @_;
    my $lexicon = $self->lexicon_map_get($lang);
    if (! $lexicon) {
        $lexicon = $self->build_storage();
        $self->lexicon_map_set($lang, $lexicon);
    }
    $lexicon->set($id, $value);
}

sub lexicon_merge {
    my ($self, $lang, $new_lexicon) = @_;

    my $lexicon = $self->lexicon_map_get($lang);
    if (! $lexicon) {
        $lexicon = $self->_build_storage($lang);
        $self->lexicon_map_set($lang, $lexicon);
    }
    while (my ($key, $value) = each %$new_lexicon) {
        $lexicon->set($key, $value);
    }
}

sub _build_storage {
    my ($self, $lang) = @_;

    my $class = $self->storage_class;
    my $args  = $self->storage_args;
    my %args;

    if ($class !~ s/^\+//) {
        $class = "Data::Localize::Storage::$class";
    }
    Any::Moose::load_class($class);

    if ( $class->isa('Data::Localize::Storage::BerkeleyDB') ) {
        my $dir  = ($args->{dir} ||= tempdir(CLEANUP => 1));
        return $class->new(
            bdb_class => 'Hash',
            bdb_args  => {
                -Filename => File::Spec->catfile($dir, $lang),
                -Flags    => BerkeleyDB::DB_CREATE(),
            }
        );
    } else {
        return $class->new();
    }
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=head1 NAME

Data::Localize::Railsy - Acquire Lexicons from F<.yml> files in a Rails-like format

=head1 DESCRIPTION

I really hate working with the Gettext format because the interface
strings in the primary language are used as the keys, e.g.:

    # Outputs "Hellow, John Doe!"
    $loc->localize( 'Hellow, [_1]!', 'John Doe' );

I much prefer the Java Property list / MediaWiki / Ruby on Rails way
of using an abstract key in my source code which then gets looked up
in a locale file, e.g.:

In my F<en.yml>:

    en:
      greetings:
        hellow: "Hellow, {{name}}"

In my code:

    # Outputs "Hellow, John Doe!"
    $loc->set_languages('en');
    $loc->localize( 'greetings.hellow', { name => 'John Doe' } );

And that's exactly what this module allows you to do. It's based on
L<Data::Localize::Gettext> with some guts ripped out and other bits
added.

To use it with L<Catalyst> add the L<Catalyst::Model::Data::Localize>
model and put something like this in your application configuration:
    
    <Model::Data::Localize>
        auto 1
        <localizers>
            class Railsy
            path  lib/MyApp/I18N/*.yml
        </localizers>
    </Model::Data::Localize>

Then in F<lib/MyApp/I18N/en.yml> put something like this:


    ---
    en:
      sayhi: "hello there {{name}}"
      stuff:
        blah: "I'm blathering"

Then you can spew out:

    # hello there You
    $loc->localize( 'sayhi', { name => 'You' } );
    # I'm blathering
    $loc->localize( 'stuff.blah' );

That's pretty much it, it doesn't support any of the other fancy stuff
Rails does like plurals (see
L<http://guides.rubyonrails.org/i18n.html>)

=head1 METHODS

=head2 lexicon_get($lang, $id)

Gets the specified lexicon

=head2 lexicon_set($lang, $id, $value)

Sets the specified lexicon

=head2 lexicon_merge

Merges lexicon (may change...)

=head2 load_from_file

Loads lexicons from specified file

=head2 load_from_path

Loads lexicons from specified path. May contain glob()'able expressions.

=head2 register

Registeres this localizer

=head1 UTF8 

Currently, strings are assumed to be utf-8,

=head1 AUTHOR

E<AElig>var ArnfjE<ouml>rE<eth> Bjarmason <avar@cpan.org>

Based on work by Daisuke Maki C<< <daisuke@endeworks.jp> >>

=head1 COPYRIGHT

=over 4

=item The "MIT" License

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=back

=cut
