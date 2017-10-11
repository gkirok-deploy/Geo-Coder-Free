package Geo::Coder::Free;

use strict;
use warnings;

use Geo::Coder::Free::DB::admin1;
use Geo::Coder::Free::DB::admin2;
use Geo::Coder::Free::DB::cities;
use Module::Info;
use Carp;
use Error::Simple;
use File::Spec;

=head1 NAME

Geo::Coder::Free - Provides a geocoding functionality using free databases of towns

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

      use Geo::Coder::Free;

      my $geocoder = Geo::Coder::Free->new();
      my $location = $geocoder->geocode(location => 'Ramsgate, Kent, UK');

=head1 DESCRIPTION

Geo::Coder::Free provides an interface to free databases.

=head1 METHODS

=head2 new

    $geocoder = Geo::Coder::Free->new();

=cut

sub new {
	my($proto, %param) = @_;
	my $class = ref($proto) || $proto;

	# Geo::Coder::Free->new not Geo::Coder::Free::new
	return unless($class);

	# Geo::Coder::Free::DB::init(directory => 'lib/Geo/Coder/Free/databases');

	my $directory = Module::Info->new_from_loaded(__PACKAGE__)->file();
	$directory =~ s/\.pm$//;
	Geo::Coder::Free::DB::init(directory => File::Spec->catfile($directory, 'databases'));

	return bless { }, $class;
}

=head2 geocode

    $location = $geocoder->geocode(location => $location);

    print 'Latitude: ', $location->{'latt'}, "\n";
    print 'Longitude: ', $location->{'longt'}, "\n";

    # TODO:
    # @locations = $geocoder->geocode('Portland, USA');
    # diag 'There are Portlands in ', join (', ', map { $_->{'state'} } @locations);
 	
=cut

sub geocode {
	my $self = shift;

	my %param;
	if (@_ % 2 == 0) {
		%param = @_;
	} else {
		$param{location} = shift;
	}

	my $location = $param{location}
		or Carp::croak("Usage: geocode(location => \$location)");

	my $county;
	my $state;
	my $country;
	my $concatenated_codes;

	if($location =~ /^([\w\s\-]+)?,([\w\s]+),([\w\s]+)?$/) {
		# Turn 'Ramsgate, Kent, UK' into 'Ramsgate'
		$location = $1;
		$county = $2;
		$country = $3;
		$location =~ s/\-/ /g;
		$county =~ s/^\s//g;
		$county =~ s/\s$//g;
		$country =~ s/^\s//g;
		$country =~ s/\s$//g;
		if($location =~ /^St\.? (.+)/) {
			$location = "Saint $1";
		}
		if(($country eq 'UK') || ($country eq 'United Kingdom')) {
			$country = 'Great Britain';
			$concatenated_codes = 'GB';
		}
	} elsif($location =~ /^([\w\s\-]+)?,([\w\s]+),([\w\s]+),\s*(Canada|United States|USA|US)?$/) {
		$location = $1;
		$county = $2;
		$state = $3;
		$country = $4;
		$county =~ s/^\s//g;
		$county =~ s/\s$//g;
		$state =~ s/^\s//g;
		$state =~ s/\s$//g;
		$country =~ s/^\s//g;
		$country =~ s/\s$//g;
	} else {
		Carp::croak(__PACKAGE__, ' only supports towns, not full addresses');
	}

	if($country) {
		if(!defined($self->{'admin1'})) {
			$self->{'admin1'} = Geo::Coder::Free::DB::admin1->new() or die "Can't open the admin1 database";
		}
		if(my $admin1 = $self->{'admin1'}->fetchrow_hashref(asciiname => $country)) {
			$concatenated_codes = $admin1->{'concatenated_codes'};
		} else {
			require Locale::Country;
			if($state) {
				if($state =~ /^[A-Z]{2}$/) {
					$concatenated_codes = uc(Locale::Country::country2code($country)) . ".$state";
				} else {
					$concatenated_codes = uc(Locale::Country::country2code($country));
					if($state) {
						my @admin1s = @{$self->{'admin1'}->selectall_hashref(asciiname => $state)};
						foreach my $admin1(@admin1s) {
							if($admin1->{'concatenated_codes'} =~ /^$concatenated_codes\./i) {
								$concatenated_codes = $admin1->{'concatenated_codes'};
								last;
							}
						}
					}
				}
			} else {
				$concatenated_codes = uc(Locale::Country::country2code($country));
			}
		}
	}
	return unless(defined($concatenated_codes));

	if(!defined($self->{'admin2'})) {
		$self->{'admin2'} = Geo::Coder::Free::DB::admin2->new() or die "Can't open the admin1 database";
	}
	my @admin2s;
	my $region;
	if($county =~ /^[A-Z]{2}/) {
		# Canadian province or US state
		$region = $county;
	} else {
		@admin2s = @{$self->{'admin2'}->selectall_hashref(asciiname => $county)};
		foreach my $admin2(@admin2s) {
			if($admin2->{'concatenated_codes'} =~ $concatenated_codes) {
				$region = $admin2->{'concatenated_codes'};
				if($region =~ /^[A-Z]{2}\.([A-Z]{2})\./) {
					my $rc = $1;
					if($state =~ /^[A-Z]{2}$/) {
						if($state eq $rc) {
							$region = $rc;
							last;
						}
					} else {
						$region = $rc;
						last;
					}
				}
			}
		}
		if($state && !defined($region)) {
			if($state =~ /^[A-Z]{2}$/) {
				$region = $state;
			} else {
				@admin2s = @{$self->{'admin2'}->selectall_hashref(asciiname => $state)};
				foreach my $admin2(@admin2s) {
					if($admin2->{'concatenated_codes'} =~ $concatenated_codes) {
						$region = $admin2->{'concatenated_codes'};
						last;
					}
				}
			}
		}
	}

	if(!defined($region)) {
		# e.g. Unitary authorities in the UK
		@admin2s = @{$self->{'admin2'}->selectall_hashref(asciiname => $location)};
		if(scalar(@admin2s) && defined($admin2s[0]->{'concatenated_codes'})) {
			foreach my $admin2(@admin2s) {
				if($admin2->{'concatenated_codes'} =~ $concatenated_codes) {
					$region = $admin2->{'concatenated_codes'};
					last;
				}
			}
		} else {
			# e.g. states in the US
			my @admin1s = @{$self->{'admin1'}->selectall_hashref(asciiname => $county)};
			foreach my $admin1(@admin1s) {
				if($admin1->{'concatenated_codes'} =~ /^$concatenated_codes\./i) {
					$region = $admin1->{'concatenated_codes'};
					last;
				}
			}
		}
	}

	if(!defined($self->{'cities'})) {
		$self->{'cities'} = Geo::Coder::Free::DB::cities->new();
	}

	my $options = { City => lc($location) };
	if($region) {
		if($region =~ /^.+\.(.+)$/) {
			$region = $1;
		}
		$options->{'Region'} = $region;
	}

	if(wantarray) {
		return @{$self->{'cities'}->selectall_hashref($options)};
	}
	return $self->{'cities'}->fetchrow_hashref($options);
	# my $rc;
	# if(wantarray && $rc->{'otherlocations'} && $rc->{'otherlocations'}->{'loc'} &&
	   # (ref($rc->{'otherlocations'}->{'loc'}) eq 'ARRAY')) {
		# my @rc = @{$rc->{'otherlocations'}->{'loc'}};
		# if(scalar(@rc)) {
			# return @rc;
		# }
	# }
	# return $rc;
	# my @results = @{ $data || [] };
	# wantarray ? @results : $results[0];
}

=head2 reverse_geocode

    $location = $geocoder->reverse_geocode(latlng => '37.778907,-122.39732');

Similar to geocode except it expects a latitude/longitude parameter.

=cut

sub reverse_geocode {
	my $self = shift;

	my %param;
	if (@_ % 2 == 0) {
		%param = @_;
	} else {
		$param{latlng} = shift;
	}

	my $latlng = $param{latlng}
		or Carp::croak("Usage: reverse_geocode(latlng => \$latlng)");

	return $self->geocode(location => $latlng, reverse => 1);
};

=head1 AUTHOR

Nigel Horne <njh@bandsman.co.uk>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 BUGS

CSV files take a long time to load.  Convert to SQLite.

Lots of lookups fail at the moment.

=head1 SEE ALSO

VWF, Maxmind and geonames.

=head1 LICENSE AND COPYRIGHT

Copyright 2017 Nigel Horne.

This program is released under the following licence: GPL2

=cut

1;
