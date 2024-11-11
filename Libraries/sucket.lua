local sucket = {}

--------------------------------------------------

--- An encoding function for sending messages over the network.  
--- 
--- Takes in any value which should be sent and returns a string of the encoded value, or potentially errors.  
--- 
--- If this isn't supplied, a simple `tostring` will be used.
---@type fun(value: any): string
sucket.encode = nil

--- A decoding function for decoding messages which arrived over the network.  
--- 
--- Takes in the encoded string value, and returns two values: a boolean whether decoding was successful, and the decoded value itself (or potentially an error message string). This function shouldn't error.
--- 
--- If this isn't supplied, arriving messages won't be decoded at all and will simply be kept as strings.
---@type fun(msg: string): boolean, any
sucket.decode = nil

--------------------------------------------------

return sucket