
class LaserTail

    constructor: (@container) ->
        # Create a Raphael canvas
        @paper = Raphael(@container, 320, 200)
        # Create some data containers
        @hits = []
        @hostHeight = 12
        @urlHeight = 12
        @leftWidth = 210
        @rightWidth = 210
        @laserDecay = 5
        @hostExpiry = 5
        @urlExpiry = 5
        # Set up resizing and expiry
        @resizeRenderer()
        window.addEventListener('resize', (=> @resizeRenderer()), false)
        @expireOld()

    # Resizes the main viewport to match the current window
    resizeRenderer: ->
        @width = $(@container).width()
        @height = $(@container).height()
        @paper.setSize(@width, @height, false)
        # Reset the hosts and urls to empty lists of the right length
        @hosts = (null for i in [0..Math.floor(@height/@hostHeight)])
        @urls = (null for i in [0..Math.floor(@height/@urlHeight)])


    # Redraws the page
    redraw: ->
        # For every host without a div, give it one, and set positions
        for host, index in @hosts
            if host?
                # Make a div if needed
                if !host.div
                    host.div = $("<div class='host'>" + host.name + "</div>")
                    $(@container).append(host.div)
                    # Set position
                    middle = (@hostHeight * index) + (@hostHeight / 2)
                    $(host.div).css({left: -@leftWidth, top: middle - (@hostHeight / 2)}).animate({left: 0})
                    host.point = [@leftWidth, middle]
        # Same for URLs
        for url, index in @urls
            if url?
                # Make a div if needed
                if !url.div
                    url.div = $("<div class='url'>" + url.path + "</div>")
                    $(@container).append(url.div)
                    # Set position
                    middle = (@urlHeight * index) + (@urlHeight / 2)
                    $(url.div).css({right: -@rightWidth, top: middle - (@urlHeight / 2)}).animate({right: 0})
                    url.point = [@width - @rightWidth, middle]
        # Draw any hits in the queue
        for hit in @hits
            host = @getHost(hit.hostName)
            url = @getUrl(hit.urlPath)
            path = @paper.path("M" + host.point[0] + "," + host.point[1] + "L" + url.point[0] + "," + url.point[1])
            path.attr("stroke", "#aad")
            path.attr("stroke-width", "3")
            ((path, delay) => 
                path.animate({opacity: 0}, delay, "linear", ->
                    path.remove();
                )
            )(path, @laserDecay * 1000)
        @hits = []

    # Gets a host by name
    getHost: (hostName) ->
        for host in @hosts
            if host? and host.name == hostName
                return host
        return undefined

    # Gets a url by path
    getUrl: (urlPath) ->
        for url in @urls
            if url? and url.path == urlPath
                return url
        return undefined

    # Places an object into an array in the place with the biggest gap
    placeArray: (array, thing) ->
        for member, index in array
            if not member?
                array[index] = thing
                return

    # Adds a hit to the page
    addHit: (hostName, urlPath, noRedraw) ->
        time = (new Date()).getTime() / 1000
        # Add a host record if there isn't one
        host = @getHost(hostName)
        if host?
            host.lastSeen = time
        else
            @placeArray(@hosts, {name: hostName, lastSeen: time})
        # Same with urls
        url = @getUrl(urlPath)
        if url?
            url.lastSeen = time
        else
            @placeArray(@urls, {path: urlPath, lastSeen: time})
        # Queue up a laser line draw
        @hits.push({hostName: hostName, urlPath: urlPath})
        # Refresh the view if needed
        if !noRedraw
            @redraw()

    # Adds many hits to the page at once
    addHits: (hits) ->
        for hit in hits
            @addHit(hit.host, hit.url, true)
        @redraw()

    # Runs a task to fetch hits from a polling server
    fetchHits: (url) ->
        # Create a watchdog in case the connection drops
        ((oldSince) => setTimeout((=>
            if oldSince == @since
                @fetchHits(url)
        ), 5000))(@since)
        # Get the JSON
        $.getJSON(url + "?since=" + @since, (data) =>
            @addHits(data.hits)
            @since = data.since
            setTimeout((=> @fetchHits(url)), 1000)
        )

    # A task to expire old URLs/hosts
    expireOld: ->
        time = (new Date()).getTime() / 1000
        for host, index in @hosts
            if host? and (time - host.lastSeen) > @hostExpiry
                $(host.div).animate({left: -@leftWidth}, -> $(this).remove())
                @hosts[index] = null
        for url, index in @urls
            if url? and (time - url.lastSeen) > @urlExpiry
                $(url.div).animate({right: -@rightWidth}, -> $(this).remove())
                @urls[index] = null
        setTimeout((=> @expireOld()), 1000)

window.LaserTail = LaserTail
