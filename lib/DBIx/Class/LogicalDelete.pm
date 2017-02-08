package DBIx::Class::LogicalDelete;
use 5.008001;
use strict;
use warnings;

our $VERSION = "0.01";

use base qw/DBIx::Class/;
use Data::Dumper;

my $skip = 0;

sub insert {
    my $self = shift;
    return $self->next::method(@_) if $skip;

    my $result_source = $self->result_source;

    my $unique_constraints = { $result_source->unique_constraints };

    my $lookup = sub {
        my ($key) = @_;

        my $columns = $unique_constraints->{$key};

        return {
            map {
                my $value = $self->get_column($_) or return;
                $_ => $value;
            } @$columns
        };
    };

    my @searches = map { $lookup->($_) } keys %$unique_constraints;

    for (@searches) {
        my $cond = { %$_, deleted => 1 };
        $skip = 1;
        $result_source->resultset->search($cond)->delete();
        $skip = 0;
    }

    return $self->next::method(@_);
}

sub all {
    my $self = shift;
    return $self->next::method(@_) if $skip;

    $skip = 1;
    my @all = $self->search({ deleted => 0 })->all;
    $skip = 0;
    return @all;
}

sub search_rs {
    my $self = shift;
    return $self->next::method(@_) if $skip;

    $skip = 1;
    my $rs = $self->search({ deleted => 0 })->search(@_);
    $skip = 0;

    return $rs;
}

sub delete {
    my $self = shift;
    return $self->next::method(@_) if $skip;

    return $self->update({ deleted => 1 });
}


1;
__END__

=encoding utf-8

=head1 NAME

DBIx::Class::LogicalDelete - It's new $module

=head1 SYNOPSIS

    use DBIx::Class::LogicalDelete;

=head1 DESCRIPTION

DBIx::Class::LogicalDelete is ...

=head1 LICENSE

Copyright (C) Keith Broughton.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Keith Broughton E<lt>keithbro256@gmail.comE<gt>

=cut

