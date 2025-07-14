#include <stdint.h>

#define BORDER_COLOUR 0xD020

int main() {
  volatile uint8_t* border = (uint8_t *)BORDER_COLOUR;
  uint8_t colour = 0;
  while(1) {
    *border = colour++;
  }

  // never reaches here
  return 0;
}
