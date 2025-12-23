const std = @import("std");
pub const libusb = @import("libusb");

pub const Allocator = std.mem.Allocator;

/// High-level error set for libusb. No C error codes leak into the public API.
pub const UsbError = error{
    Io,
    InvalidParam,
    Access,
    NoDevice,
    NotFound,
    Busy,
    Timeout,
    Overflow,
    Pipe,
    Interrupted,
    NoMem,
    NotSupported,
    Other,
};

fn mapLibusbError(code: c_int) UsbError {
    return switch (code) {
        libusb.LIBUSB_ERROR_IO => UsbError.Io,
        libusb.LIBUSB_ERROR_INVALID_PARAM => UsbError.InvalidParam,
        libusb.LIBUSB_ERROR_ACCESS => UsbError.Access,
        libusb.LIBUSB_ERROR_NO_DEVICE => UsbError.NoDevice,
        libusb.LIBUSB_ERROR_NOT_FOUND => UsbError.NotFound,
        libusb.LIBUSB_ERROR_BUSY => UsbError.Busy,
        libusb.LIBUSB_ERROR_TIMEOUT => UsbError.Timeout,
        libusb.LIBUSB_ERROR_OVERFLOW => UsbError.Overflow,
        libusb.LIBUSB_ERROR_PIPE => UsbError.Pipe,
        libusb.LIBUSB_ERROR_INTERRUPTED => UsbError.Interrupted,
        libusb.LIBUSB_ERROR_NO_MEM => UsbError.NoMem,
        libusb.LIBUSB_ERROR_NOT_SUPPORTED => UsbError.NotSupported,
        libusb.LIBUSB_ERROR_OTHER => UsbError.Other,
        else => UsbError.Other,
    };
}

fn checkResult(rc: c_int) UsbError!void {
    if (rc >= 0) return;
    return mapLibusbError(rc);
}

/// USB connection speed (mirrors libusb_speed but as a Zig enum).
pub const Speed = enum(u8) {
    unknown,
    low,
    full,
    high,
    super,
    super_plus,

    fn fromLibusb(value: c_int) Speed {
        return switch (value) {
            libusb.LIBUSB_SPEED_UNKNOWN => .unknown,
            libusb.LIBUSB_SPEED_LOW => .low,
            libusb.LIBUSB_SPEED_FULL => .full,
            libusb.LIBUSB_SPEED_HIGH => .high,
            libusb.LIBUSB_SPEED_SUPER => .super,
            libusb.LIBUSB_SPEED_SUPER_PLUS => .super_plus,
            else => .unknown,
        };
    }
};

/// Direction bit for endpoints and control transfers.
pub const Direction = enum(u8) {
    out = libusb.LIBUSB_ENDPOINT_OUT,
    in = libusb.LIBUSB_ENDPOINT_IN,
};

/// Transfer type for endpoints.
pub const TransferType = enum(u8) {
    control = libusb.LIBUSB_TRANSFER_TYPE_CONTROL,
    isochronous = libusb.LIBUSB_TRANSFER_TYPE_ISOCHRONOUS,
    bulk = libusb.LIBUSB_TRANSFER_TYPE_BULK,
    interrupt = libusb.LIBUSB_TRANSFER_TYPE_INTERRUPT,
    bulk_stream = libusb.LIBUSB_TRANSFER_TYPE_BULK_STREAM, // usb 3.0
};

/// Request type field in bmRequestType.
pub const RequestType = enum(u8) {
    standard = libusb.LIBUSB_REQUEST_TYPE_STANDARD,
    class = libusb.LIBUSB_REQUEST_TYPE_CLASS,
    vendor = libusb.LIBUSB_REQUEST_TYPE_VENDOR,
    reserved = libusb.LIBUSB_REQUEST_TYPE_RESERVED,
};

/// Recipient field in bmRequestType.
pub const Recipient = enum(u8) {
    device = libusb.LIBUSB_RECIPIENT_DEVICE,
    interface = libusb.LIBUSB_RECIPIENT_INTERFACE,
    endpoint = libusb.LIBUSB_RECIPIENT_ENDPOINT,
    other = libusb.LIBUSB_RECIPIENT_OTHER,
};

/// Helper to construct bmRequestType from high-level enums.
pub fn makeBmRequestType(
    dir: Direction,
    req_type: RequestType,
    recipient: Recipient,
) u8 {
    return @intFromEnum(dir) | @intFromEnum(req_type) | @intFromEnum(recipient);
}

/// High-level view of a USB device descriptor.
pub const DeviceDescriptor = struct {
    usb_bcd: u16,
    device_class: u8,
    device_subclass: u8,
    device_protocol: u8,
    max_packet_size_0: u8,
    vendor_id: u16,
    product_id: u16,
    device_bcd: u16,
    manufacturer_str_index: u8,
    product_str_index: u8,
    serial_number_str_index: u8,
    num_configurations: u8,

    fn fromLibusb(desc: libusb.libusb_device_descriptor) DeviceDescriptor {
        return .{
            .usb_bcd = desc.bcdUSB,
            .device_class = desc.bDeviceClass,
            .device_subclass = desc.bDeviceSubClass,
            .device_protocol = desc.bDeviceProtocol,
            .max_packet_size_0 = desc.bMaxPacketSize0,
            .vendor_id = desc.idVendor,
            .product_id = desc.idProduct,
            .device_bcd = desc.bcdDevice,
            .manufacturer_str_index = desc.iManufacturer,
            .product_str_index = desc.iProduct,
            .serial_number_str_index = desc.iSerialNumber,
            .num_configurations = desc.bNumConfigurations,
        };
    }
};

/// Endpoint address helper: direction + 4-bit endpoint number.
pub const EndpointAddress = struct {
    number: u8, // 0..15
    direction: Direction,

    pub fn toRaw(self: EndpointAddress) u8 {
        const dir_bit: u8 = switch (self.direction) {
            .out => libusb.LIBUSB_ENDPOINT_OUT,
            .in => libusb.LIBUSB_ENDPOINT_IN,
        };
        return (self.number & 0x0F) | dir_bit;
    }

    pub fn fromRaw(raw: u8) EndpointAddress {
        const dir: Direction = if ((raw & libusb.LIBUSB_ENDPOINT_IN) != 0)
            .in
        else
            .out;
        return .{
            .number = raw & 0x0F,
            .direction = dir,
        };
    }
};

/// A libusb context. Create this once per process (or once per library user).
pub const Context = struct {
    raw: *libusb.libusb_context,

    /// Initialize libusb. Must be called before anything else.
    pub fn init() UsbError!Context {
        var ctx: ?*libusb.libusb_context = null;
        const rc = libusb.libusb_init(&ctx);
        try checkResult(rc);
        return Context{ .raw = ctx.? };
    }

    /// Deinitialize libusb. After this, handles derived from this Context are invalid.
    pub fn deinit(self: *Context) void {
        libusb.libusb_exit(self.raw);
    }

    /// Optional: set libusb log level (0..4).
    pub fn setLogLevel(level: u32) i32 {
        // _ = self; // not needed by libusb in this call
        return @intCast(libusb.libusb_set_option(
            null,
            libusb.LIBUSB_OPTION_LOG_LEVEL,
            @as(c_int, @intCast(level)),
        ));
    }

    /// Open a device by vendor/product ID.
    ///
    /// Returns `null` if no such device is present, or a `DeviceHandle` on success.
    pub fn openDeviceByVidPid(
        self: *Context,
        vendor_id: u16,
        product_id: u16,
    ) UsbError!?DeviceHandle {
        const handle = libusb.libusb_open_device_with_vid_pid(
            self.raw,
            vendor_id,
            product_id,
        );
        if (handle == null) return null;
        return DeviceHandle{
            .ctx = self,
            .raw = handle.?,
        };
    }
};

/// An open handle to a USB device, associated with a Context.
pub const DeviceHandle = struct {
    ctx: *Context,
    raw: *libusb.libusb_device_handle,

    /// Close the device handle.
    pub fn close(self: *DeviceHandle) void {
        libusb.libusb_close(self.raw);
    }

    /// Reset the device (USB bus-level reset).
    pub fn reset(self: *DeviceHandle) UsbError!void {
        const rc = libusb.libusb_reset_device(self.raw);
        try checkResult(rc);
    }

    /// Set the active configuration number.
    pub fn setConfiguration(self: *DeviceHandle, config_value: u8) UsbError!void {
        const rc = libusb.libusb_set_configuration(
            self.raw,
            @intCast(config_value), // inferred as c_int
        );
        try checkResult(rc);
    }

    /// Get the currently active configuration value.
    pub fn getConfiguration(self: *DeviceHandle) UsbError!u8 {
        var cfg: c_int = 0;
        const rc = libusb.libusb_get_configuration(self.raw, &cfg);
        try checkResult(rc);
        return @intCast(cfg); // inferred as u8
    }

    pub fn setAutoDetachKernelDriver(self: *DeviceHandle, enable: bool) UsbError!void {
        const rc = libusb.libusb_set_auto_detach_kernel_driver(
            self.raw,
            @intFromBool(enable),
        );
        try checkResult(rc);
    }

    /// Claim an interface on this device.
    pub fn claimInterface(self: *DeviceHandle, iface: u8) UsbError!void {
        const rc = libusb.libusb_claim_interface(
            self.raw,
            @intCast(iface),
        );
        try checkResult(rc);
    }

    /// Release a previously claimed interface.
    pub fn releaseInterface(self: *DeviceHandle, iface: u8) UsbError!void {
        const rc = libusb.libusb_release_interface(
            self.raw,
            @intCast(iface),
        );
        try checkResult(rc);
    }

    /// Get the low-level bus number and device address.
    pub fn getBusAndAddress(self: *DeviceHandle) struct { bus: u8, address: u8 } {
        const dev = libusb.libusb_get_device(self.raw);
        const bus = libusb.libusb_get_bus_number(dev);
        const addr = libusb.libusb_get_device_address(dev);
        return .{ .bus = bus, .address = addr };
    }

    /// Get the link speed (low/full/high/super/...).
    pub fn getSpeed(self: *DeviceHandle) Speed {
        const dev = libusb.libusb_get_device(self.raw);
        const s = libusb.libusb_get_device_speed(dev);
        return Speed.fromLibusb(s);
    }

    /// Get the device descriptor.
    pub fn getDeviceDescriptor(self: *DeviceHandle) UsbError!DeviceDescriptor {
        const dev = libusb.libusb_get_device(self.raw);
        var raw_desc: libusb.libusb_device_descriptor = undefined;
        const rc = libusb.libusb_get_device_descriptor(dev, &raw_desc);
        try checkResult(rc);
        return DeviceDescriptor.fromLibusb(raw_desc);
    }

    /// Read an ASCII string descriptor into `buf` and return the subslice used.
    ///
    /// `index` is the string descriptor index from the device descriptor.
    pub fn getStringDescriptorAscii(
        self: *DeviceHandle,
        index: u8,
        buf: []u8,
    ) UsbError![]u8 {
        if (buf.len == 0) return buf[0..0];

        const rc = libusb.libusb_get_string_descriptor_ascii(
            self.raw,
            index,
            buf.ptr,
            @intCast(buf.len),
        );
        if (rc < 0) return mapLibusbError(rc);
        return buf[0..@intCast(rc)];
    }

    // ------------------------------------------------------------
    // Control transfers
    // ------------------------------------------------------------

    /// Generic control transfer (IN or OUT).
    ///
    /// For OUT, `data` is the payload to send.
    /// For IN, `data` is the receive buffer.
    /// Returns the number of bytes actually transferred.
    pub fn controlTransfer(
        self: *DeviceHandle,
        dir: Direction,
        req_type: RequestType,
        recipient: Recipient,
        bRequest: u8,
        wValue: u16,
        wIndex: u16,
        data: []u8,
        timeout_ms: u32,
    ) UsbError!usize {
        const bmRequestType: u8 = makeBmRequestType(dir, req_type, recipient);

        const data_ptr: [*c]u8 = if (data.len > 0)
            @ptrCast(@constCast(data.ptr))
        else
            null;

        const rc = libusb.libusb_control_transfer(
            self.raw,
            bmRequestType,
            bRequest,
            wValue,
            wIndex,
            data_ptr,
            @intCast(data.len),
            timeout_ms,
        );
        if (rc < 0) return mapLibusbError(rc);
        return @intCast(rc);
    }

    /// Convenience wrapper for a control OUT transfer.
    pub fn controlOut(
        self: *DeviceHandle,
        req_type: RequestType,
        recipient: Recipient,
        bRequest: u8,
        wValue: u16,
        wIndex: u16,
        data: []const u8,
        timeout_ms: u32,
    ) UsbError!usize {
        return self.controlTransfer(
            .out,
            req_type,
            recipient,
            bRequest,
            wValue,
            wIndex,
            @ptrCast(@constCast(data.ptr)),
            timeout_ms,
        );
    }

    /// Convenience wrapper for a control IN transfer.
    /// Fills `buf` and returns the number of bytes read.
    pub fn controlIn(
        self: *DeviceHandle,
        req_type: RequestType,
        recipient: Recipient,
        bRequest: u8,
        wValue: u16,
        wIndex: u16,
        buf: []u8,
        timeout_ms: u32,
    ) UsbError!usize {
        return self.controlTransfer(
            .in,
            req_type,
            recipient,
            bRequest,
            wValue,
            wIndex,
            buf,
            timeout_ms,
        );
    }

    // ------------------------------------------------------------
    // Bulk transfers
    // ------------------------------------------------------------

    /// Bulk OUT transfer: send `data` to `endpoint` (e.g. 0x01).
    /// Returns bytes actually sent.
    pub fn bulkOut(
        self: *DeviceHandle,
        endpoint: EndpointAddress,
        data: []const u8,
        timeout_ms: u32,
    ) UsbError!usize {
        try ensureLenFitsCInt(data.len);

        var actual: c_int = 0;

        const rc = libusb.libusb_bulk_transfer(
            self.raw,
            endpoint.toRaw(),
            @ptrCast(@constCast(data.ptr)),
            @intCast(data.len),
            &actual,
            timeout_ms,
        );
        try checkResult(rc);
        return @intCast(actual);
    }

    /// Bulk IN transfer: receive into `buf` from `endpoint` (e.g. 0x81).
    /// Returns bytes actually received.
    pub fn bulkIn(
        self: *DeviceHandle,
        endpoint: EndpointAddress,
        buf: []u8,
        timeout_ms: u32,
    ) UsbError!usize {
        try ensureLenFitsCInt(buf.len);

        var actual: c_int = 0;
        const rc = libusb.libusb_bulk_transfer(
            self.raw,
            endpoint.toRaw(),
            buf.ptr,
            @intCast(buf.len),
            &actual,
            timeout_ms,
        );
        try checkResult(rc);
        return @intCast(actual);
    }

    // ------------------------------------------------------------
    // Interrupt transfers
    // ------------------------------------------------------------

    /// Interrupt OUT transfer.
    pub fn interruptOut(
        self: *DeviceHandle,
        endpoint: EndpointAddress,
        data: []const u8,
        timeout_ms: u32,
    ) UsbError!usize {
        try ensureLenFitsCInt(data.len);

        var actual: c_int = 0;
        const rc = libusb.libusb_interrupt_transfer(
            self.raw,
            endpoint.toRaw(),
            @ptrCast(@constCast(data.ptr)),
            @intCast(data.len),
            &actual,
            timeout_ms,
        );
        try checkResult(rc);
        return @intCast(actual);
    }

    /// Interrupt IN transfer.
    pub fn interruptIn(
        self: *DeviceHandle,
        endpoint: EndpointAddress,
        buf: []u8,
        timeout_ms: u32,
    ) UsbError!usize {
        try ensureLenFitsCInt(buf.len);

        var actual: c_int = 0;
        const rc = libusb.libusb_interrupt_transfer(
            self.raw,
            endpoint.toRaw(),
            buf.ptr,
            @intCast(buf.len),
            &actual,
            timeout_ms,
        );
        try checkResult(rc);
        return @intCast(actual);
    }
};

fn ensureLenFitsCInt(len: usize) UsbError!void {
    if (len > @as(usize, std.math.maxInt(c_int))) {
        return UsbError.InvalidParam;
    }
}

/// Optional: friendly human-readable error string for debugging/logging.
pub fn errorToString(err: UsbError) []const u8 {
    return switch (err) {
        .Io => "I/O error",
        .InvalidParam => "Invalid parameter",
        .Access => "Access denied",
        .NoDevice => "No such device",
        .NotFound => "Entity not found",
        .Busy => "Resource busy",
        .Timeout => "Timeout",
        .Overflow => "Overflow",
        .Pipe => "Pipe error",
        .Interrupted => "Interrupted system call",
        .NoMem => "Out of memory",
        .NotSupported => "Operation not supported",
        .Other => "Other USB error",
    };
}
