// host_transport_libusb.c

#include <libusb-1.0/libusb.h>
#include <stdio.h>

static libusb_context *g_ctx = NULL;
static libusb_device_handle *g_dev = NULL;

static uint8_t g_iface_number = 0;
static uint8_t g_ep_in = 0;
static uint8_t g_ep_out = 0;

static void debug_print_config(const struct libusb_config_descriptor *cfg) {
  printf("Config %u: %u interfaces\n", cfg->bConfigurationValue,
         cfg->bNumInterfaces);

  for (int i = 0; i < cfg->bNumInterfaces; i++) {
    const struct libusb_interface *iface = &cfg->interface[i];
    for (int a = 0; a < iface->num_altsetting; a++) {
      const struct libusb_interface_descriptor *ifd = &iface->altsetting[a];
      printf("  IF %d alt %d: class=0x%02x, eps=%u\n", ifd->bInterfaceNumber,
             ifd->bAlternateSetting, ifd->bInterfaceClass, ifd->bNumEndpoints);

      for (int e = 0; e < ifd->bNumEndpoints; e++) {
        const struct libusb_endpoint_descriptor *ep = &ifd->endpoint[e];
        printf("    EP 0x%02x: attr=0x%02x, maxPacket=%u\n",
               ep->bEndpointAddress, ep->bmAttributes, ep->wMaxPacketSize);
      }
    }
  }
}

int transport_init(uint16_t vid, uint16_t pid) {
  int r = libusb_init(&g_ctx);
  if (r < 0) {
    fprintf(stderr, "libusb_init failed: %s\n", libusb_error_name(r));
    return r;
  }

  libusb_device **list = NULL;
  ssize_t cnt = libusb_get_device_list(g_ctx, &list);
  if (cnt < 0) {
    fprintf(stderr, "libusb_get_device_list: %s\n",
            libusb_error_name((int)cnt));
    return (int)cnt;
  }

  libusb_device *found_dev = NULL;
  struct libusb_device_descriptor dd;

  for (ssize_t i = 0; i < cnt; i++) {
    libusb_device *dev = list[i];
    r = libusb_get_device_descriptor(dev, &dd);
    if (r < 0)
      continue;

    if (dd.idVendor == vid && dd.idProduct == pid) {
      found_dev = dev;
      break;
    }
  }

  if (!found_dev) {
    fprintf(stderr, "No device %04x:%04x found\n", vid, pid);
    libusb_free_device_list(list, 1);
    return -1;
  }

  r = libusb_open(found_dev, &g_dev);
  if (r < 0) {
    fprintf(stderr, "libusb_open failed: %s\n", libusb_error_name(r));
    libusb_free_device_list(list, 1);
    return r;
  }

  libusb_free_device_list(list, 1);

  printf("Device opened: %04x:%04x, bNumConfigurations=%u\n", dd.idVendor,
         dd.idProduct, dd.bNumConfigurations);

  // Iterate all configurations and find a vendor-specific interface with bulk
  // IN+OUT
  int found_iface = 0;
  uint8_t cfg_value_for_iface = 0;

  for (uint8_t cfgIdx = 0; cfgIdx < dd.bNumConfigurations && !found_iface;
       cfgIdx++) {
    struct libusb_config_descriptor *cfg = NULL;
    r = libusb_get_config_descriptor(found_dev, cfgIdx, &cfg);
    if (r < 0) {
      fprintf(stderr, "get_config_descriptor(%u) failed: %s\n", cfgIdx,
              libusb_error_name(r));
      continue;
    }

    debug_print_config(cfg); // very useful while debugging

    for (int i = 0; i < cfg->bNumInterfaces && !found_iface; i++) {
      const struct libusb_interface *iface = &cfg->interface[i];
      for (int a = 0; a < iface->num_altsetting && !found_iface; a++) {
        const struct libusb_interface_descriptor *ifd = &iface->altsetting[a];

        if (ifd->bInterfaceClass != LIBUSB_CLASS_VENDOR_SPEC)
          continue;

        uint8_t ep_in = 0, ep_out = 0;

        for (int e = 0; e < ifd->bNumEndpoints; e++) {
          const struct libusb_endpoint_descriptor *ep = &ifd->endpoint[e];
          if ((ep->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) !=
              LIBUSB_TRANSFER_TYPE_BULK)
            continue;

          if (ep->bEndpointAddress & LIBUSB_ENDPOINT_IN)
            ep_in = ep->bEndpointAddress;
          else
            ep_out = ep->bEndpointAddress;
        }

        if (ep_in && ep_out) {
          g_iface_number = ifd->bInterfaceNumber;
          g_ep_in = ep_in;
          g_ep_out = ep_out;
          cfg_value_for_iface = cfg->bConfigurationValue;
          found_iface = 1;
        }
      }
    }

    libusb_free_config_descriptor(cfg);
  }

  if (!found_iface) {
    fprintf(stderr,
            "Could not find vendor-specific interface with bulk IN/OUT\n");
    return -1;
  }

  printf("Using config %u, interface %u, EP_IN=0x%02x, EP_OUT=0x%02x\n",
         cfg_value_for_iface, g_iface_number, g_ep_in, g_ep_out);

  // // Ensure that configuration is active (if not already)
  // r = libusb_set_configuration(g_dev, cfg_value_for_iface);
  // if (r < 0 && r != LIBUSB_ERROR_BUSY) {
  //   // BUSY here typically means it was already set, which is fine
  //   fprintf(stderr, "libusb_set_configuration(%u) failed: %s\n",
  //           cfg_value_for_iface, libusb_error_name(r));
  //   return r;
  // }

  // Detach kernel driver from that interface if needed
  int active = libusb_kernel_driver_active(g_dev, g_iface_number);
  if (active == 1) {
    printf("Kernel driver active on IF %u, detaching...\n", g_iface_number);
    r = libusb_detach_kernel_driver(g_dev, g_iface_number);
    if (r < 0) {
      fprintf(stderr, "detach_kernel_driver failed: %s\n",
              libusb_error_name(r));
    }
  }

  r = libusb_claim_interface(g_dev, g_iface_number);
  if (r < 0) {
    fprintf(stderr, "claim_interface(%u) failed: %s\n", g_iface_number,
            libusb_error_name(r));
    return r;
  }

  printf("transport_init OK\n");
  return 0;
}

int transport_send(const void *buf, int len) {
  printf("sending %d bytes\n", len);
  int xfer = 0;
  int r = libusb_bulk_transfer(g_dev, g_ep_out, (unsigned char *)buf, len,
                               &xfer, 1000);
  if (r != 0) {
    fprintf(stderr, "bulk OUT error: %s (%d)\n", libusb_error_name(r), r);
    return -1;
  }
  if (xfer != len) {
    fprintf(stderr, "bulk OUT short xfer: %d of %d\n", xfer, len);
    return -1;
  }
  return xfer;
}

int transport_recv(void *buf, int len, int timeout_ms) {
  int xfer = 0;
  int r = libusb_bulk_transfer(g_dev, g_ep_in, (unsigned char *)buf, len, &xfer,
                               timeout_ms);
  if (r == LIBUSB_ERROR_TIMEOUT)
    return 0;
  if (r != 0) {
    fprintf(stderr, "bulk IN error: %s (%d)\n", libusb_error_name(r), r);
    return -1;
  }
  return xfer;
}

void transport_close(void) {
  if (g_dev) {
    libusb_release_interface(g_dev, g_iface_number);
    libusb_close(g_dev);
    g_dev = NULL;
  }
  if (g_ctx) {
    libusb_exit(g_ctx);
    g_ctx = NULL;
  }
}
