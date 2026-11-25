wa_download: wa_download.swift
	swiftc -O wa_download.swift -o wa_download

clean:
	rm -f wa_download

.PHONY: clean
