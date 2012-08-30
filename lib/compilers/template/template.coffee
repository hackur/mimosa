path = require 'path'
fs = require 'fs'

wrench = require 'wrench'

fileUtils = require '../../util/file'
logger = require '../../util/logger'
minifier = require '../../util/minify'

AbstractCompiler = require '../compiler'

module.exports = class AbstractTemplateCompiler extends AbstractCompiler

  constructor: (config) ->
    super(config, config.compilers.template)
    @templateFileName = path.join(@compDir, @config.outputFileName + ".js")
    if @clientLibrary?
      @mimosaClientLibraryPath = path.join __dirname, "client", "#{@clientLibrary}.js"
      @clientPath = path.join path.dirname(@templateFileName), 'vendor', "#{@clientLibrary}.js"
    @notifyOnSuccess = config.growl.onSuccess.template

    if @fullConfig.min
      @minifier = minifier.setExclude(@fullConfig.minify.exclude)

  # OVERRIDE THIS
  compile: (fileNames, callback) ->
    throw new Error "Method compile(fileNames, callback) must be implemented"

  created: =>
    if @startupFinished then @_gatherFiles() else @done()

  updated: =>
    @_gatherFiles()

  removed: (fileName) =>
    @_gatherFiles true
    @optimize(fileName)

  cleanup: ->
    @_removeClientLibrary()
    @removeTheFile(@templateFileName, false) if fs.existsSync @templateFileName

  doneStartup: ->
    @_gatherFiles()

  _gatherFiles: (isRemove = false) ->
    logger.debug "Gathering files for templates"
    fileNames = []
    allFiles = wrench.readdirSyncRecursive(@srcDir)
      .map (file) => path.join(@srcDir, file)

    for file in allFiles
      extension = path.extname(file).substring(1)
      fileNames.push(file) if @config.extensions.indexOf(extension) >= 0

    if fileNames.length is 0
      if isRemove
        logger.debug "No template files left, removing [[ #{@templateFileName} ]]"
        @removeTheFile @templateFileName
        @_removeClientLibrary()
    else
      @_testForSameTemplateName(fileNames)
      @_writeClientLibrary =>
        if @_templateNeedsCompiling fileNames
          AbstractTemplateCompiler::done = =>
            @_reportStartupDone() if !@startupFinished
          @compile fileNames, @_write
        else
          @_reportStartupDone()

  _testForSameTemplateName: (fileNames) ->
    templateHash = {}
    for fileName in fileNames
      templateName = path.basename(fileName, path.extname(fileName))
      if templateHash[templateName]?
        logger.error "Files [[ #{templateHash[templateName]} ]] and [[ #{fileName} ]] result in templates of the same name " +
                     "being created.  You will want to change the name for one of them or they will collide."
      else
        templateHash[templateName] = fileName

  _templateNeedsCompiling: (fileNames) ->
    for file in fileNames
      if @fileNeedsCompiling(file, @templateFileName)
        logger.debug "Template file [[ #{@templateFileName} ]] needs compiling"
        return true

    logger.debug "Template file [[ #{@templateFileName} ]] does not need compiling"
    false

  _write: (error, output) =>
    if error
      @failed error
    else
      if output?
        if @minifier?
          output = @minifier.minify(@templateFileName, output)
        @write(@templateFileName, output)

  _reportStartupDone: =>
    unless @startupFinished
      @startupDoneCallback()
      @startupFinished = true

  _removeClientLibrary: ->
    if @clientPath? and fs.existsSync @clientPath
      logger.debug "Removing client library [[ #{@clientPath} ]]"
      fs.unlink @clientPath

  _writeClientLibrary: (callback) ->
    if @fullConfig.virgin or !@clientPath? or fs.existsSync @clientPath
      logger.debug "Not going to write template client library"
      return callback()

    logger.debug "Writing template client library [[ #{@mimosaClientLibraryPath} ]]"
    fs.readFile @mimosaClientLibraryPath, "ascii", (err, data) =>
      if err?
        logger.error("Cannot read client library: #{@mimosaClientLibraryPath}") if err?
        return callback()

      if @minifier?
        data = @minifier.minify(@clientPath, data)

      fileUtils.writeFile @clientPath, data, (err) =>
        @failed("Cannot write client library: #{err}") if err?
        callback()

  templatePreamble: (fileName, templateName) ->
    """
    \n//
    // Source file: [#{fileName}]
    // Template name: [#{templateName}]
    //\n
    """

  addTemplateToOutput: (fileName, templateName, source) =>
    """
    #{@templatePreamble(fileName, templateName)}
    templates['#{templateName}'] = #{source};\n
    """

  afterWrite: (fileName) ->
    @optimize(fileName)
