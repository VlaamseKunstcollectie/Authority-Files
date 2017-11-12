#!perl

# Fetches VIAF alternate names for a dataset of VIAF uri's and returns them
# as a single CSV file. 
#
# Usage:
#   perl viaf.pl --type CSV < import.csv > export.csv
#	perl viaf.pl --type JSON < import.json > export.csv
#
# This script will perform an RDF LDF request against the Linked Data Fragments
# server hosted at http://data.linkeddatafragments.org/viaf. Alternatively,
# you can host your own local LDF server containing the VIAF data and point the
# $viaf_endpoint variable to that server.
#
# Your input dataset requires a viaf_uri property with valid VIAF URI's. 
# Alternate names will be stored in the alternate_name property.
#
# More information: 
# 	https://librecatproject.wordpress.com/2015/06/03/matching-authors-against-viaf-identities/
# 
# Author: Matthias Vandermaesen <matthias dot vandermaesen at vlaamsekunstcollectie dot be>
# License: GPLv3 <https://www.gnu.org/licenses/gpl-3.0.en.html>
#

use Catmandu::Sane;
use Catmandu;
use Cache::LRU;
use RDF::LDF;
use Getopt::Long;

my $importer  = undef;

GetOptions("fix=s" => \$fix , "importer=s" => \$importer);
my $query     = shift;

unless ($query) {
    print STDERR <<EOF;
usage: $0 [--importer [CSV|JSON] file
EOF
    exit(1);
}

my $iterator;

if (-r $query) {
    $iterator  = Catmandu->importer($importer, file => $query);
} else {
    print STDERR <<EOF;
usage: $0 [--importer [CSV|JSON] file
File does not exist.
EOF
    exit(1);
}

my $viaf_endpoint = 'http://data.linkeddatafragments.org/viaf';
my $client    = RDF::LDF->new(url => $viaf_endpoint);
my $cache     = Cache::LRU->new(size => 10000);

binmode(STDOUT,':encoding(UTF-8)');

&do_import();

sub do_import {
	my $fix		= shift;
	my $query	= shift;
	my $fixer;

	my $exporter = Catmandu->exporter('CSV');

	my $n = $iterator->each(sub {
		my $item	= shift;
		my $uri		= $item->{viaf_uri};

		if (defined $uri) {
			$item->{alternate_name} = &viaf_get_id($uri);	
		} else {
			$item->{alternate_name} = '';
		}

		$exporter->add($item);
	});
}

sub viaf_get_id {
	my $key 	= shift;

    if (defined(my $value = $cache->get($key))) {
        return $value;
    }
    else {
        my $value = &ldf_query($key);
        $cache->set($key => $value);
        return $value;
    }
}

sub ldf_query {
    my $subject = shift;
    my $it = $client->get_statements($subject, 'http://schema.org/alternateName', undef);

    my @res = ();
    while (my $st = $it->()) {
        push @res, $st->object->literal_value;
    }

    return join(';', @res);
}

	