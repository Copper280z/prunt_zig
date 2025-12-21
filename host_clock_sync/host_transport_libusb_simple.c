// host_transport_libusb.c

#include "host_time.h"
#include "sync_protocol.h"
#include <libusb-1.0/libusb.h>
#include <stdio.h>

static libusb_context *g_ctx = NULL;
static libusb_device_handle *g_dev = NULL;

static uint8_t g_iface_number = 2; // adjust if your vendor IF is not 0
static uint8_t g_ep_in = 0x87;
static uint8_t g_ep_out = 0x07;

int transport_init(uint16_t vid, uint16_t pid) {
  int r = libusb_init(&g_ctx);
  if (r < 0) {
    fprintf(stderr, "libusb_init failed: %d\n", r);
    return r;
  }

  libusb_device **list = NULL;
  ssize_t cnt = libusb_get_device_list(g_ctx, &list);
  if (cnt < 0) {
    fprintf(stderr, "libusb_get_device_list: %zd\n", cnt);
    return (int)cnt;
  }

  libusb_device *found = NULL;
  struct libusb_device_descriptor desc;
  for (ssize_t i = 0; i < cnt; i++) {
    libusb_device *dev = list[i];
    r = libusb_get_device_descriptor(dev, &desc);
    if (r < 0) {
      continue;
    }

    if (desc.idVendor == vid && desc.idProduct == pid) {
      printf("Found candidate device: bus %u, address %u\n",
             libusb_get_bus_number(dev), libusb_get_device_address(dev));
      printf("  bNumConfigurations = %u\n", desc.bNumConfigurations);
      found = dev;
      break;
    }
  }

  if (!found) {
    fprintf(stderr, "No device with VID:PID %04x:%04x found\n", vid, pid);
    libusb_free_device_list(list, 1);
    return -1;
  }

  // Open with detailed error reporting
  r = libusb_open(found, &g_dev);
  if (r < 0) {
    fprintf(stderr, "libusb_open failed: %s (%d)\n", libusb_error_name(r), r);
    fprintf(stderr, "Hint: if this is LIBUSB_ERROR_ACCESS, try running as root "
                    "or add a udev rule.\n");
    libusb_free_device_list(list, 1);
    return r;
  }

  libusb_free_device_list(list, 1);

  // (Optional) set configuration explicitly if needed:
  // r = libusb_set_configuration(g_dev, 1);
  // if (r < 0) {
  //     fprintf(stderr, "libusb_set_configuration failed: %s\n",
  //     libusb_error_name(r)); return r;
  // }

  // Detach any kernel driver on that interface
  int active = libusb_kernel_driver_active(g_dev, g_iface_number);
  if (active == 1) {
    printf("Kernel driver active on interface %u, detaching...\n",
           g_iface_number);
    r = libusb_detach_kernel_driver(g_dev, g_iface_number);
    if (r < 0) {
      fprintf(stderr, "libusb_detach_kernel_driver failed: %s\n",
              libusb_error_name(r));
      // not fatal if we purposely want to see this
    }
  }

  r = libusb_claim_interface(g_dev, g_iface_number);
  if (r < 0) {
    fprintf(stderr, "libusb_claim_interface(%u) failed: %s (%d)\n",
            g_iface_number, libusb_error_name(r), r);
    fprintf(stderr, "Hint: LIBUSB_ERROR_BUSY => kernel driver still bound, or "
                    "wrong interface.\n");
    return r;
  }

  printf("Successfully opened and claimed interface %u on %04x:%04x\n",
         g_iface_number, vid, pid);

  return 0;
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

int transport_send(const void *buf, int len) {
  int transferred = 0;
  int r = libusb_bulk_transfer(g_dev, g_ep_out, (unsigned char *)buf, len,
                               &transferred, 10);
  if (r != 0 || transferred != len) {
    fprintf(stderr, "bulk OUT error r=%s (%d), xfer=%d\n", libusb_error_name(r),
            r, transferred);
    return -1;
  }
  return transferred;
}

int transport_recv(void *buf, int len, int timeout_ms) {
  int transferred = 0;
  int r = libusb_bulk_transfer(g_dev, g_ep_in, (unsigned char *)buf, len,
                               &transferred, timeout_ms);
  if (r == LIBUSB_ERROR_TIMEOUT)
    return 0;
  if (r != 0) {
    fprintf(stderr, "bulk IN error r=%s (%d)\n", libusb_error_name(r), r);
    return -1;
  }
  return transferred;
}
