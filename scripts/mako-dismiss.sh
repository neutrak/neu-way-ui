#!/bin/bash

makoctl list | jq  >> /tmp/mako-dismissed-notifications.log
makoctl dismiss -a

