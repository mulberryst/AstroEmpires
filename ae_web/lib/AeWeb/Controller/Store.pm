package AeWeb::Controller::Store;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
use Mojo::IOLoop;
use Mojo::Util qw/dumper/;
use URI::Escape;
use URI;
use DateTime;
use DBI;
use Try::Tiny;
use DateTime::Format::DateManip;
use Date::Manip;

sub storeData
{
  my ($s, $ae) = @_;

  my $dbh = DBI->connect_cached("DBI:mysql:database=ae;",'ae', 'q1w2e3r4', {'RaiseError' => 1, AutoCommit => 1}) || die $DBI::errstr;

  my ($server, $time, $playerId, $daysOld) = ($ae->{'server'}, $ae->{'time'}, $ae->{'playerID'}, $ae->{daysOld});
  map { delete $ae->{$_}; } qw/server time playerID daysOld/;

  my $dtServer = DateTime::Format::DateManip->parse_datetime(ParseDate($time));

#  for now i dont want old data
#
  if (defined $daysOld) {
    my $dtData = $dtServer->clone->subtract(days => $daysOld);
    return;
  }

  if (exists $ae->{url} and exists $ae->{msg} and exists $ae->{stack}) {
    my $sth = $dbh->prepare(qq/
      insert into aegisErrors (server, time, playerID, url, msg, stack)
      values(?,?,?,?,?,?)
      on duplicate key update
        time      = values(time),
        count = (count +1)
       /);
    try {
      $sth->execute($server, $time, $playerId, $ae->{url}, $ae->{msg}, $ae->{stack});
    } catch {
      die "error insert: $_";
    };
    return;
  }

  foreach my $dbTable (keys %$ae) {
    if ($dbTable eq 'player') {

      foreach my $id (keys %{$ae->{player}}) {
        my $p = $ae->{player}->{$id};
        my $guild = $p->{guild};

        my $sth = $dbh->prepare(qq/
        insert into player
          (server, time, playerId, id, name, level, upgraded, guildTag, guildId, guildName)
        values
          (?,?,?,?,?,?,?,?,?,?)
        on duplicate key update
          time      = values(time),
          name      = values(name),
          level     = ifnull(values(level), level),
          upgraded  = ifnull(values(upgraded), upgraded),
          guildTag  = values(guildTag),
          guildId   = ifnull(values(guildId),guildId),
          guildName = ifnull(values(guildName), guildName)
          /);

        my $i = 1;
        $sth->bind_param($i++, $server);
        $sth->bind_param($i++, $time);
        $sth->bind_param($i++, $playerId);
        $sth->bind_param($i++, $id);
        $sth->bind_param($i++, $p->{name});
        $sth->bind_param($i++, $p->{level});
        $sth->bind_param($i++, $p->{upgraded});
        $sth->bind_param($i++, $guild->{tag});
        $sth->bind_param($i++, $guild->{id});
        $sth->bind_param($i++, $guild->{name});
        try {
          $sth->execute();
        } catch {
          die "player upsert: $_";
        };

      }
    } elsif ($dbTable eq 'astro') {
      foreach my $loc (keys %{$ae->{astro}}) {
        my $e = $ae->{astro}->{$loc};

        my $sth = $dbh->prepare(qq/
        insert into astro
          (server,time,playerId,location,terrain,type,base, unknownFleet, unknownIncoming)
        values
          (?,?,?,?,?,?,?,?,?)
        on duplicate key update 
          time = values(time),
          terrain = values(terrain),
          type = values(type),
          base = values(base),
          unknownFleet = values(unknownFleet),
          unknownIncoming = values(unknownIncoming)
        /);
        my $i = 1;
        $sth->bind_param($i++, $server);
        $sth->bind_param($i++, $time);
        $sth->bind_param($i++, $playerId);
        $sth->bind_param($i++, $loc);
        $sth->bind_param($i++, $e->{terrain});
        $sth->bind_param($i++, $e->{type});
        $sth->bind_param($i++, $e->{base});
        $sth->bind_param($i++, $e->{unknownFleet});
        $sth->bind_param($i++, $e->{unknownIncoming});

        try {
          $sth->execute();
        } catch {
          die "astro upsert: $_";
        };
      }

    } elsif ($dbTable eq 'base') {
      foreach my $id (keys %{$ae->{base}}) {
        my $e = $ae->{base}->{$id};

        my $sth = $dbh->prepare(qq/
        insert into base
          (server,time,playerId,id,name,location,owner,occupier,economy,ownerIncome,tradeRoutes,commandCenters,jumpGate)
        values
          (?,?,?,?,?,?,?,?,?,?,?,?,?)
        on duplicate key update
          time      = values(time),
          name      = ifnull(values(name),name),
          owner      = values(owner),
          occupier      = ifnull(values(occupier),occupier),
          economy      = ifnull(values(economy),economy),
          ownerIncome      = ifnull(values(ownerIncome),ownerIncome),
          tradeRoutes      = ifnull(values(tradeRoutes),tradeRoutes),
          commandCenters      = ifnull(values(commandCenters), commandCenters),
          jumpGate      = ifnull(values(jumpGate), jumpGate)
          /);
        my $i = 1;
        $sth->bind_param($i++, $server);
        $sth->bind_param($i++, $time);
        $sth->bind_param($i++, $playerId);
        $sth->bind_param($i++, $id);
        $sth->bind_param($i++, $e->{name});
        $sth->bind_param($i++, $e->{location});
        $sth->bind_param($i++, $e->{owner});
        $sth->bind_param($i++, $e->{occupier});
        $sth->bind_param($i++, $e->{economy});
        $sth->bind_param($i++, $e->{ownerIncome});
        $sth->bind_param($i++, $e->{tradeRoutes});
        $sth->bind_param($i++, $e->{commandCenters});
        $sth->bind_param($i++, $e->{jumpGate});
        try {
          $sth->execute();
        } catch {
          die "base upsert: $_";
        };

        $sth = $dbh->prepare(qq/update astro set base = ? where server = ? and location = ?/);
        try {
          $sth->execute($id, $server, $e->{location});
        } catch {
          warn "astro base update: $_";
        };

        if (exists $e->{defenses}) {
          $e = $e->{defenses};
          $sth = $dbh->prepare(qq/
          insert into base
            (server,playerId,id,barracks,laserTurrets,missileTurrets,ionTurrets,photonTurrets,disruptorTurrets,deflectionShields,planetaryShields,planetaryRing)
          values
            (?,?,?,?,?,?,?,?,?,?,?,?)
          on duplicate key update
            barracks      = values(barracks),
            laserTurrets      = values(laserTurrets),
            missileTurrets      = values(missileTurrets),
            ionTurrets      = values(ionTurrets),
            photonTurrets      = values(photonTurrets),
            disruptorTurrets      = values(disruptorTurrets),
            deflectionShields      = values(deflectionShields),
            planetaryShields      = values(planetaryShields),
            planetaryRing      = values(planetaryRing)
          /);

          $i = 1;
          $sth->bind_param($i++, $server);
          $sth->bind_param($i++, $playerId);
          $sth->bind_param($i++, $id);
          $sth->bind_param($i++, $e->{Barracks});
          $sth->bind_param($i++, $e->{'Laser Turrets'});
          $sth->bind_param($i++, $e->{'Missile Turrets'});
          $sth->bind_param($i++, $e->{'Ion Turrets'});
          $sth->bind_param($i++, $e->{'Photon Turrets'});
          $sth->bind_param($i++, $e->{'Disruptor Turrets'});
          $sth->bind_param($i++, $e->{'Deflection Shields'});
          $sth->bind_param($i++, $e->{'Planetary Shields'});
          $sth->bind_param($i++, $e->{'Planetary Ring'});

          try {
            $sth->execute();
          } catch {
            die "base upsert: $_";
          };
        }
      }
    } elsif ($dbTable eq 'fleet') {
      foreach my $id (keys %{$ae->{$dbTable}}) {
        my $e = $ae->{$dbTable}->{$id};
# parseMapFleet
        if (not exists $e->{ships}) {
          my $sth = $dbh->prepare(qq/
              delete from fleet where server = ? and location = ?
              /);
          try {
            $sth->execute($server, $e->{location});
          } catch {
            die "removing fleet: $_";
          };
        }

        my $sth = $dbh->prepare(qq/
        insert into fleet
          (server,time,playerId,id,name,player,size,origin,location,arrival,ships)
        values
          (?,?,?,?,?,?,?,?,?,?,?)
        on duplicate key update 
          time = values(time),
          name = ifnull(values(name),name),
          player = values(player),
          size = values(size),
          origin = ifnull(values(origin), origin),
          location = values(location),
          arrival = values(arrival),
          ships = ifnull(values(ships), ships)
        /);

        my $i = 1;
        $sth->bind_param($i++, $server);
        $sth->bind_param($i++, $time);
        $sth->bind_param($i++, $playerId);
        $sth->bind_param($i++, $id);
        $sth->bind_param($i++, $e->{name});
        $sth->bind_param($i++, $e->{player});
        $sth->bind_param($i++, $e->{size});
        $sth->bind_param($i++, $e->{origin});
        $sth->bind_param($i++, $e->{location});

        my $arrival = undef;
        if (exists $e->{arrival}) {
          my $dtArrival = $dtServer->clone->add(seconds => $e->{arrival});
          $arrival = $dtArrival->strftime("%Y-%m-%d %I:%M:%S %p");
        }
        $sth->bind_param($i++, $arrival);

        my $ships = undef;
        if (exists $e->{ships}) {
          my $es = $e->{ships};
          $ships = join('|', map { "$_:".$es->{$_}; } keys %$es);
        }
        $sth->bind_param($i++, $ships);
        try {
          $sth->execute();
        } catch {
          die "fleet upsert: $_";
        };
      }
    }
  }
}

sub dumpPostData {
  my $s = shift;

  $s->app->log->info($s->req->headers->header('x-real-ip'));
  $s->app->log->debug($s->req->body);

  my $json = Mojo::JSON->new;

  my $aeData = $json->decode( $s->req->body );
  my $err  = $json->error;

  if ($json->error) {
    $s->stash(json => { error => $json->error });
    $s->render(status => 400);
    #$s->render(template => 'main/response', format => 'json');
  } else {

    try {
      $s->storeData($aeData);

      $s->app->log->debug("storeData succeeded");
      $s->stash(json => { response => 'sahksess' });
      $s->render(status => 200);
    } catch {
        $s->app->log->debug("error: $_");
        $s->stash(json => {response => $_ });
        $s->render(status => 500);
    };
  }
}

1;