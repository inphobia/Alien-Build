package Alien::Build::Plugin::Fetch::CurlCommand;

use strict;
use warnings;
use 5.008001;
use Alien::Build::Plugin;
use File::Which qw( which );
use Path::Tiny qw( path );
use Capture::Tiny qw( capture );
use File::Temp qw( tempdir );
use File::chdir;

# ABSTRACT: Curl command line plugin for fetching files
# VERSION

has curl_command => sub { which('curl') };
has ssl => 0;
has _see_headers => 0;

sub init
{
  my($self, $meta) = @_;

  $meta->register_hook(
    fetch => sub {
      my($build, $url) = @_;
      $url ||= $meta->prop->{start_url};

      my($scheme) = $url =~ /^([a-z0-9]+):/i;
      
      unless($scheme =~ /^https?$/)
      {
        die "scheme $scheme is not supported by the Fetch::CurlCommand plugin";
      }
      
      local $CWD = tempdir( CLEANUP => 1 );
      
      path('writeout')->spew(
        join("\\n",
          "ab-filename     :%{filename_effective}",
          "ab-content_type :%{content_type}",
          "ab-url          :%{url_effective}",
        ),
      );
      
      my @command = (
        $self->curl_command,
        '-L', '-O', '-J',
        -w => '@writeout',
      );
      
      push @command, -D => 'head' if $self->_see_headers;
      
      push @command, $url;
      
      $build->log("+ @command");
      my($stdout, $stderr, $err) = capture {
        system(@command);
        $?;
      };
      die "Error in curl fetch" if $err;

      my %h = map { my($k,$v) = m/^ab-(.*?)\s*:(.*)$/; $k => $v } split /\n/, $stdout;

      $build->log(" ~ $_ => $h{$_}") for sort keys %h;
      if(-e 'head')
      {
        $build->log(" header: $_") for path('headers')->lines;
      }
      
      my($type) = split ';', $h{content_type};

      # TODO: test for FTP to see what the content-type is, if any      
      if($type eq 'text/html')
      {
        return {
          type    => 'html',
          base    => $h{url},
          content => scalar path($h{filename})->slurp,
        };
      }
      else
      {
        return {
          type     => 'file',
          filename => $h{filename},
          path     => path($h{filename})->absolute->stringify,
        };
      }
      
    },
  );
  
  $self;  
}

1;