# The Simple Thermostat / NV Energy ECO Factor Homekit Bridge

This is a homekit bridge for The Simple Theromstat / NV Energy ECO Factor devices. I've only tested it with S100 devices. The code is bad, it's a spike, but it works. I can now set the temperature using home or siri.

## Install

* install ruby 2.6.6 (recommend: ruby-build)
* gem install bundler
* clone this repo

```bash
bundle install
THESIMPLE_BEARER_TOKEN=xxxxxxxxxxx bundle exec ruby main.rb
```

## Todo

* set the on / off / heat / cool state properly on the termostat
* mutli location
* figure out docker / k8s - doesn't work on linux due to avahi issues / me being dumb