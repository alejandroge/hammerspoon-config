# Hammerspoon configuration

This is my personal Hammerspoon configuration. It is a collection of scripts and snippets that I use to automate tasks and improve my workflow on macOS.

## Installation
1. Install [Hammerspoon](https://www.hammerspoon.org/)
2. Place the contents of the repo `~/.hammerspoon/`

### Secrets

I'm using a `secrets.lua` file to store some sensitive information that is used in the scripts. The file should look
like this (or just copy the `secrets.example.lua` file and fill in your own values):

```lua
return {
  wifiHome = "SSID for Home network",
}
```
