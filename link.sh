#!/bin/sh

for name in *.pl
do
	chmod 755 $name
	rm $HOME/bin/${name%.pl}
	ln -s $PWD/$name $HOME/bin/${name%.pl}
done

