use Test::Most;

use File::Temp qw/tempfile/;
use Data::Dumper;


{
    package TestDB::Schema;
    use base qw(DBIx::Class::Schema);
    use strict;
    use warnings;

    sub create_table {
        my $class = shift;
        $class->storage->dbh_do(
            sub {
                my ($storage, $dbh, @cols) = @_;
                $dbh->do(q{
                    CREATE TABLE foo (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name VARCHAR(255) UNIQUE,
                        deleted TINYINT DEFAULT 0
                    );
                });
            },
        );
    }

    1;

    package TestDB::Schema::Foo;
    use strict;
    use warnings;
    use base qw/DBIx::Class/;

    __PACKAGE__->load_components(qw/LogicalDelete Core/);
    __PACKAGE__->table('foo');
    __PACKAGE__->add_columns(qw(id name deleted));
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->add_unique_constraint([ qw/name/ ]);
    __PACKAGE__->resultset_class('TestDB::Schema::ResultSet::Foo');

    1;

    package TestDB::Schema::ResultSet::Foo;

    use strict;
    use warnings;

    use base 'DBIx::Class::ResultSet';
    __PACKAGE__->load_components(qw/LogicalDelete/);
}

my (undef, $dbname) = tempfile();
my $schema = TestDB::Schema->connection("dbi:SQLite:dbname=$dbname");

ok($schema->create_table, 'create table');

TestDB::Schema->load_classes('Foo');

# Problem with insert:
#
# $rs->new({ a => 1, b => 2 })->insert();
#
# It's complicated to figure out the unique key combinations and what
# to do. For each unique constraint we could search for "deleted" rows
# that match the criteria of the new row. If one is found, delete it for
# real, and do the insert. This insert may still fail if a non-deleted
# row exists and conflicts.
#

my $foo_rs = $schema->resultset('Foo');

$foo_rs->new({ name => $_ })->insert() for 1..3;
assert_foos(
    [
        { id => 1, name => 1, deleted => 0 },
        { id => 2, name => 2, deleted => 0 },
        { id => 3, name => 3, deleted => 0 },
    ],
    '$row->insert',
);

$foo_rs->find(1)->delete();
assert_foos(
    [
        { id => 1, name => 1, deleted => 1 },
        { id => 2, name => 2, deleted => 0 },
        { id => 3, name => 3, deleted => 0 },
    ],
    '$row->delete',
);

eq_or_diff(
    [ map { $_->id } $foo_rs->all ],
    [ 2, 3 ],
    'all only returns non-deleted',
);

eq_or_diff(
    [ map { $_->id } $foo_rs->search() ],
    [ 2, 3 ],
    'search only returns non-deleted',
);

$foo_rs->new({ id => 1 })->insert();
assert_foos(
    [
        { id => 1, name => undef, deleted => 0 },
        { id => 2, name => 2, deleted => 0 },
        { id => 3, name => 3, deleted => 0 },
    ],
);

$foo_rs->new({ name => 'hello' })->insert();
assert_foos(
    [
        { id => 1, name => undef, deleted => 0 },
        { id => 2, name => 2, deleted => 0 },
        { id => 3, name => 3, deleted => 0 },
        { id => 4, name => 'hello', deleted => 0 },
    ]
);

$foo_rs->find(4)->delete();
assert_foos(
    [
        { id => 1, name => undef, deleted => 0 },
        { id => 2, name => 2, deleted => 0 },
        { id => 3, name => 3, deleted => 0 },
        { id => 4, name => 'hello', deleted => 1 },
    ]
);

$foo_rs->new({ name => 'hello' })->insert();
assert_foos(
    [
        { id => 1, name => undef, deleted => 0 },
        { id => 2, name => 2, deleted => 0 },
        { id => 3, name => 3, deleted => 0 },
        { id => 5, name => 'hello', deleted => 0 },
    ]
);

throws_ok(
    sub { $foo_rs->new({ name => 'hello' })->insert() },
    qr/UNIQUE constraint failed: foo.name/,
);
assert_foos(
    [
        { id => 1, name => undef, deleted => 0 },
        { id => 2, name => 2, deleted => 0 },
        { id => 3, name => 3, deleted => 0 },
        { id => 5, name => 'hello', deleted => 0 },
    ]
);

# Result Set
$foo_rs->delete();
assert_foos(
    [
        { id => 1, name => undef, deleted => 1 },
        { id => 2, name => 2, deleted => 1 },
        { id => 3, name => 3, deleted => 1 },
        { id => 5, name => 'hello', deleted => 1 },
    ],
);

$foo_rs->create({ name => 2 });
assert_foos(
    [
        { id => 1, name => undef, deleted => 1 },
        { id => 3, name => 3, deleted => 1 },
        { id => 5, name => 'hello', deleted => 1 },
        { id => 6, name => 2, deleted => 0 },
    ],
);


sub assert_foos {
    eq_or_diff(
        [
            map { +{ $_->get_inflated_columns } }
            $schema->resultset('Foo')->all
        ],
        @_,
    );
}

done_testing;


