## Each protocol performs a role defined by a stage.
## An Stage object is a factory for its implementing protocols.
setClass("Stage", contains = "VIRTUAL")

## Common methods

## get the role identifier of a stage
setGeneric("role", function(object, ...) standardGeneric("role"))

# Stage methods

setMethod("role", "Stage",
          function(object) dequalifyStageName(class(object)))

# the factory method - creates a protocol given a method name
setMethod("protocol", "Stage",
          function(object, method = defaultMethod(object), ...)
{
  protocol <- NULL
  me <- role(object)
  class <- protocolClass(me, method)
  if (extends(class, qualifyProtocolName(me)))
    protocol <- new(class, ...)
  protocol
})

# get an Stage instance
Stage <- function(role) {
  new(qualifyStageName(role))
}
# private: do not export these name manipulation functions
dequalifyStageName <- function(name) {
  decapitalize(sub("^Stage", "", name))
}
qualifyStageName <- function(name) {
  paste("Stage", capitalize(name), sep="")
}

# to circumvent spurious warnings resulting from not using a character
# literal in the call to standardGeneric().
.dyngeneric <- function(name, args = alist(object=, ...=))
{
  as.function(c(args, substitute(standardGeneric(name), list(name=name))))
}

# stage registration
setStage <- function(name, dispname = name, intype, outtype = intype,
                     where = topenv(parent.frame()))
{
  name <- decapitalize(name)
  # register this stage as a class in the 'where' environment
  class <- setClass(qualifyStageName(name), contains = "Stage",
                    where = where)
  # create accessors for 'dispname' and 'inType'
  setMethod("dispName", class, function(object) dispname, where = where)
  setMethod("inType", class, function(object) intype, where = where)
  setMethod("outType", class, function(object) outtype, where = where)
  # create the API for performing a method of this stage
  performFunc <- function(object, method = defaultMethod(name), ...)
    {
      ### formerly resolved unnamed arguments against stage.method function
      ### that is not possible anymore and we want the user to name args anyway
      ##generic <- paste(name, decapitalize(method), sep=".")
      ##call <- as.call(list(as.name(generic), object, ...))
      ##args <- as.list(match.call(getMethodLocal(generic, intype), call))
      ##args <- tail(args, -2)
      args <- list(...)
      slots <- names(args) %in% slotNames(protocolClass(name, method))
      proto <- do.call("Protocol", c(list(name, method), args[slots]))
      do.call("perform", c(list(proto, object), args[!slots]))
    }
  if (is.null(getGeneric(name)))
    setGeneric(name, .dyngeneric(name), where = where)
  setMethod(name, intype, performFunc, where = where)
  # create a base protocol class for this stage
  protoclass <- setClass(qualifyProtocolName(name),
                         contains = c("Protocol", "VIRTUAL"), where = where)
  setMethod("inType", protoclass, function(object) intype, where = where)
  setMethod("outType", protoclass, function(object) outtype, where = where)
  # create methods for getting and setting pipeline protocols
  # not sure if this is necessary
  accessor <- paste(name, "Proto", sep="")
  setGeneric(accessor, .dyngeneric(accessor), where = where)
  setMethod(accessor, "Pipeline", function(object, method = character())
            protocol(object, name, method),
            where = where)
  setMethod(accessor, outtype, function(object, method = character())
            protocol(object@pipeline, name, method),
            where = where)
  replacer <- paste(accessor, "<-", sep="")
  setGeneric(replacer, .dyngeneric(replacer, alist(object=,value=)),
             where = where)
  setReplaceMethod(accessor, "Pipeline",
                   function(object, value)
                   {
                     protocol(object, name) <- value
                     object
                   }, where = where)
  name
}

# Protocol methods

setGeneric("defaultMethod",
           function(object, ...) standardGeneric("defaultMethod"))

setMethod("defaultMethod", "Stage",
          function(object) defaultMethod(role(object)))

.defaultMethodKey <- function(value)
  paste(decapitalize(value), "method", sep=".")

setMethod("defaultMethod", "character", function(object, ...)
          {
            key <- .defaultMethodKey(object)
            getOption("BioC")$commandr[[key]]
          })

setMethod("defaultMethod", "missing", function(object, ...) {
  args <- list(...)
  bioc <- getOption("BioC")
  if (is.null(bioc$commandr))
    bioc$commandr <- list()
  for (role in names(args)) {
    bioc$commandr[[.defaultMethodKey(role)]] <- args[[role]]
  }
  options(BioC = bioc)
})
          
setGeneric("defaultMethod<-", function(object, value)
           standardGeneric("defaultMethod<-"))

setReplaceMethod("defaultMethod", "Stage",
                 function(object, value)
                 {
                   args <- structure(list(value), names = role(object))
                   do.call("defaultMethod", args)
                   object
                 })

setGeneric("protocolClasses",
           function(object, ...) standardGeneric("protocolClasses"))
setMethod("protocolClasses", "Stage",
          function(object, where = topenv(parent.frame()))
          {
            baseProto <- qualifyProtocolName(dequalifyStageName(class(object)))
            protos <- findSubclasses(baseProto, where)
            ##subs <- names(getClass(baseProto)@subclasses)
            protos[!unlist(lapply(protos, isVirtualClass))]
          })
